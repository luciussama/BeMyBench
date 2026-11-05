//! BMyBench (Be My Bench) - benchmark core.
//!
//! Exposto ao Flutter via FFI (C ABI). Cada funcao retorna uma string JSON
//! alocada em Rust; o chamador deve liberar com `bmb_free_string`.
//!
//! Metodologia propria (nao clona Geekbench/Cinebench):
//! - CPU: mistura de inteiros (xorshift), ponto flutuante e acesso a memoria,
//!   medida em janela de tempo fixa. Score = milhoes de operacoes por segundo.
//! - Memoria: banda sequencial de leitura/escrita (GB/s) e latencia de acesso
//!   aleatorio (ns) via pointer chasing.
//!
//! As strings sao sempre ASCII, entao podem ser tratadas como UTF-8.

use std::ffi::CString;
use std::hint::black_box;
use std::os::raw::c_char;
use std::time::{Duration, Instant};

const WORK_BLOCK: u64 = 2048;

/// Bloco de trabalho: inteiros + float + memoria local (cache-friendly).
#[inline(never)]
fn cpu_work(seed: u64, blocks: u64) -> u64 {
    let mut x = seed | 1;
    let mut h: u64 = 0x9E37_79B9_7F4A_7C15;
    let mut f: f64 = 1.000_000_1;
    let mut buf = [0u64; 64];
    let mut idx: usize = 0;

    for b in 0..blocks {
        for _ in 0..WORK_BLOCK {
            // inteiros
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            h = h.wrapping_add(x).rotate_left(7);

            // float
            f = f * 1.000_000_1 + (h & 0xFFFF) as f64 * 0.5;

            // memoria (cache)
            idx = (idx + 1) & 63;
            buf[idx] = buf[idx].wrapping_add(h);
            h ^= buf[idx];

            // branch imprevisivel leve
            if h & 0x3F == 0 {
                h = h.wrapping_mul(3);
            }
        }
        // usa o bloco para evitar otimizacao total do laco externo
        x = x.wrapping_add(b);
    }

    h ^= black_box(x) ^ black_box(f.to_bits()) ^ black_box(buf[idx]);
    black_box(h)
}

fn cpu_worker(duration: Duration, seed: u64) -> u64 {
    let deadline = Instant::now() + duration;
    let mut ops: u64 = 0;
    let mut block: u64 = 1;
    while Instant::now() < deadline {
        black_box(cpu_work(seed.wrapping_add(block), 1));
        ops += WORK_BLOCK;
        block = block.wrapping_add(1);
    }
    black_box(ops)
}

fn to_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => CString::new("{\"error\":\"nul byte\"}").unwrap().into_raw(),
    }
}

/// Retorna a versao do core (util para diagnostico).
#[no_mangle]
pub extern "C" fn bmb_version() -> *mut c_char {
    to_c_string(format!("\"{}\"", env!("CARGO_PKG_VERSION")))
}

/// Benchmark de CPU.
///
/// `duration_ms`: duracao da medicao por teste (min. 200 ms).
/// `threads`: numero de threads para o teste multi-core (min. 1).
///
/// JSON: { "single_mops": f64, "multi_mops": f64, "threads": u32,
///         "duration_ms": u64, "score": f64 }
#[no_mangle]
pub extern "C" fn bmb_cpu_benchmark(duration_ms: u64, threads: u32) -> *mut c_char {
    let duration = Duration::from_millis(duration_ms.max(200));
    let nthreads = threads.max(1);

    // single-core
    let single_ops = cpu_worker(duration, 0x1234_5678_9ABC_DEF0);

    // multi-core
    let mut handles = Vec::with_capacity(nthreads as usize);
    for t in 0..nthreads {
        let d = duration;
        handles.push(std::thread::spawn(move || {
            cpu_worker(d, 0xABCD_EF01_2345_6789 ^ (t as u64).wrapping_mul(0x9E37_79B9))
        }));
    }
    let mut multi_ops: u64 = 0;
    for h in handles {
        multi_ops = multi_ops.saturating_add(h.join().unwrap_or(0));
    }

    let secs = duration.as_secs_f64();
    let single_mops = single_ops as f64 / secs / 1_000_000.0;
    let multi_mops = multi_ops as f64 / secs / 1_000_000.0;
    let score = single_mops + multi_mops;

    to_c_string(format!(
        "{{\"single_mops\":{:.3},\"multi_mops\":{:.3},\"threads\":{},\"duration_ms\":{},\"score\":{:.3}}}",
        single_mops,
        multi_mops,
        nthreads,
        duration.as_millis(),
        score
    ))
}

/// Benchmark de memoria.
///
/// `size_mb`: tamanho do buffer sequencial (clamp 8..2048).
/// `chase_entries`: entradas no pointer chasing (clamp 1k..64M).
///
/// JSON: { "write_gbps": f64, "read_gbps": f64, "copy_gbps": f64,
///         "latency_ns": f64, "size_mb": u64, "score": f64 }
#[no_mangle]
pub extern "C" fn bmb_memory_benchmark(size_mb: u64, chase_entries: u64) -> *mut c_char {
    let size_mb = size_mb.clamp(8, 2048);
    let n_u64 = (size_mb as usize * 1024 * 1024) / 8;
    let mut buf: Vec<u64> = vec![0u64; n_u64];
    let mut dst: Vec<u64> = vec![0u64; n_u64];

    // --- escrita sequencial ---
    let t0 = Instant::now();
    for (i, v) in buf.iter_mut().enumerate() {
        *v = i as u64;
    }
    let write_secs = t0.elapsed().as_secs_f64().max(1e-9);
    black_box(&buf);

    // --- leitura sequencial ---
    let t1 = Instant::now();
    let mut sum: u64 = 0;
    for v in buf.iter() {
        sum = sum.wrapping_add(*v);
    }
    let read_secs = t1.elapsed().as_secs_f64().max(1e-9);
    black_box(sum);

    // --- copia (read+write) ---
    let t2 = Instant::now();
    dst.copy_from_slice(&buf);
    let copy_secs = t2.elapsed().as_secs_f64().max(1e-9);
    black_box(&dst);

    // --- latencia: pointer chasing aleatorio ---
    let entries = chase_entries.clamp(1024, 64 * 1024 * 1024) as usize;
    let mut order: Vec<u32> = (0..entries as u32).collect();
    // permutacao deterministica (LCG + Fisher-Yates)
    let mut state: u64 = 0xDEAD_BEEF_CAFE_BABE;
    for i in (1..entries).rev() {
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let j = (state >> 33) as usize % (i + 1);
        order.swap(i, j);
    }
    let mut next: Vec<u32> = vec![0u32; entries];
    for i in 0..entries {
        next[order[i] as usize] = order[(i + 1) % entries];
    }

    let latency_start = Instant::now();
    let mut pos: usize = 0;
    let chases: u64 = (entries as u64) * 4;
    for _ in 0..chases {
        pos = next[pos] as usize;
    }
    let latency_secs = latency_start.elapsed().as_secs_f64().max(1e-9);
    let latency_ns = latency_secs / chases as f64 * 1e9;
    black_box(pos);

    let bytes = (n_u64 * 8) as f64;
    let write_gbps = bytes / write_secs / 1e9;
    let read_gbps = bytes / read_secs / 1e9;
    let copy_gbps = (bytes * 2.0) / copy_secs / 1e9;
    let score = (write_gbps + read_gbps + copy_gbps) * 100.0;

    to_c_string(format!(
        "{{\"write_gbps\":{:.3},\"read_gbps\":{:.3},\"copy_gbps\":{:.3},\"latency_ns\":{:.2},\"size_mb\":{},\"score\":{:.3}}}",
        write_gbps, read_gbps, copy_gbps, latency_ns, size_mb, score
    ))
}

/// Libera uma string retornada por este modulo.
///
/// # Safety
/// `ptr` deve ter vindo de uma das funcoes acima (ou ser nulo).
#[no_mangle]
pub unsafe extern "C" fn bmb_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    unsafe fn take(ptr: *mut c_char) -> String {
        let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        bmb_free_string(ptr);
        s
    }

    #[test]
    fn version_is_json_string() {
        let v = unsafe { take(bmb_version()) };
        assert!(v.starts_with('"') && v.ends_with('"'));
    }

    #[test]
    fn cpu_benchmark_returns_positive_score() {
        let json = unsafe { take(bmb_cpu_benchmark(200, 2)) };
        assert!(json.contains("single_mops"));
        assert!(json.contains("multi_mops"));
        assert!(json.contains("score"));
        // score nao pode ser zero
        assert!(!json.contains("\"score\":0.000"));
    }

    #[test]
    fn memory_benchmark_returns_positive_bandwidth() {
        let json = unsafe { take(bmb_memory_benchmark(8, 4096)) };
        assert!(json.contains("write_gbps"));
        assert!(json.contains("latency_ns"));
        assert!(!json.contains("\"write_gbps\":0.000"));
    }
}
