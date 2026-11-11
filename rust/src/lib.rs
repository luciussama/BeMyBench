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

#[cfg(target_os = "windows")]
mod windows_telemetry {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Mutex;
    use std::mem::zeroed;
    use std::ptr;

    /// `SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION` (NtQuerySystemInformation).
    #[repr(C)]
    #[derive(Copy, Clone, Default)]
    #[allow(dead_code)]
    struct SystemProcessorPerformanceInformation {
        idle_time: i64,
        kernel_time: i64,
        user_time: i64,
        dpc_time: i64,
        interrupt_time: i64,
        interrupt_count: u32,
        reserved: u32,
    }

    /// Classe 8: tempos por processador lógico.
    const SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION_CLASS: u32 = 8;

    /// `PDH_FMT_COUNTERVALUE` (o double fica no offset 8 por alinhamento).
    #[repr(C)]
    #[derive(Copy, Clone, Default)]
    struct PdhFmtCounterValue {
        status: u32,
        padding: u32,
        double_value: f64,
    }

    /// `PDH_FMT_COUNTERVALUE_ITEM_W`
    #[repr(C)]
    #[derive(Copy, Clone)]
    #[allow(dead_code)]
    struct PdhFmtCounterValueItemW {
        name: *mut u16,
        value: PdhFmtCounterValue,
    }

    const PDH_FMT_DOUBLE: u32 = 0x0000_0200;
    const PDH_MORE_DATA: i32 = 0x8000_07D2u32 as i32;
    const PDH_CSTATUS_VALID_DATA: u32 = 0;

    #[repr(C)]
    #[derive(Copy, Clone, Default)]
    struct FileTime {
        dw_low_date_time: u32,
        dw_high_date_time: u32,
    }

    impl FileTime {
        fn to_u64(&self) -> u64 {
            ((self.dw_high_date_time as u64) << 32) | (self.dw_low_date_time as u64)
        }
    }

    #[repr(C)]
    struct MemoryStatusEx {
        dw_length: u32,
        dw_memory_load: u32,
        ull_total_phys: u64,
        ull_avail_phys: u64,
        ull_total_page_file: u64,
        ull_avail_page_file: u64,
        ull_total_virtual: u64,
        ull_avail_virtual: u64,
        ull_avail_extended_virtual: u64,
    }

    #[link(name = "kernel32")]
    extern "system" {
        fn GetSystemTimes(
            lp_idle_time: *mut FileTime,
            lp_kernel_time: *mut FileTime,
            lp_user_time: *mut FileTime,
        ) -> i32;

        fn GlobalMemoryStatusEx(lp_buffer: *mut MemoryStatusEx) -> i32;
    }

    #[link(name = "ntdll")]
    extern "system" {
        fn NtQuerySystemInformation(
            system_information_class: u32,
            system_information: *mut u8,
            system_information_length: u32,
            return_length: *mut u32,
        ) -> i32;
    }

    #[link(name = "pdh")]
    extern "system" {
        fn PdhOpenQueryW(data_source: *const u16, user_data: usize, query: *mut isize) -> i32;
        fn PdhAddEnglishCounterW(
            query: isize,
            counter_path: *const u16,
            user_data: usize,
            counter: *mut isize,
        ) -> i32;
        fn PdhCollectQueryData(query: isize) -> i32;
        fn PdhGetFormattedCounterArrayW(
            counter: isize,
            format: u32,
            buffer_size: *mut u32,
            item_count: *mut u32,
            buffer: *mut u8,
        ) -> i32;
        fn PdhCloseQuery(query: isize) -> i32;
    }

    static PREV_IDLE: AtomicU64 = AtomicU64::new(0);
    static PREV_KERNEL: AtomicU64 = AtomicU64::new(0);
    static PREV_USER: AtomicU64 = AtomicU64::new(0);

    /// Amostra anterior por núcleo: (idle, total) em unidades de 100 ns.
    static PREV_CORES: Mutex<Vec<(u64, u64)>> = Mutex::new(Vec::new());

    pub fn get_cpu_percent() -> f64 {
        unsafe {
            let mut idle = FileTime::default();
            let mut kernel = FileTime::default();
            let mut user = FileTime::default();
            if GetSystemTimes(&mut idle, &mut kernel, &mut user) == 0 {
                return 0.0;
            }

            let cur_idle = idle.to_u64();
            let cur_kernel = kernel.to_u64();
            let cur_user = user.to_u64();

            let prev_idle = PREV_IDLE.swap(cur_idle, Ordering::Relaxed);
            let prev_kernel = PREV_KERNEL.swap(cur_kernel, Ordering::Relaxed);
            let prev_user = PREV_USER.swap(cur_user, Ordering::Relaxed);

            if prev_kernel == 0 && prev_user == 0 {
                return 0.0;
            }

            let diff_idle = cur_idle.saturating_sub(prev_idle);
            let diff_kernel = cur_kernel.saturating_sub(prev_kernel);
            let diff_user = cur_user.saturating_sub(prev_user);

            let total_sys = diff_kernel + diff_user;
            if total_sys == 0 {
                return 0.0;
            }

            let busy = total_sys.saturating_sub(diff_idle);
            let pct = (busy as f64 / total_sys as f64) * 100.0;
            pct.clamp(0.0, 100.0)
        }
    }

    /// Carga por núcleo lógico (0.0 a 100.0). Devolve vazio na primeira
    /// chamada, porque a taxa só existe depois de duas amostras.
    pub fn get_cpu_per_core() -> Vec<f64> {
        const MAX_CORES: usize = 512;
        let item_size = std::mem::size_of::<SystemProcessorPerformanceInformation>();
        let mut buffer = vec![SystemProcessorPerformanceInformation::default(); MAX_CORES];
        let mut returned: u32 = 0;

        unsafe {
            let status = NtQuerySystemInformation(
                SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION_CLASS,
                buffer.as_mut_ptr() as *mut u8,
                (MAX_CORES * item_size) as u32,
                &mut returned,
            );
            if status < 0 {
                return Vec::new();
            }

            let count = (returned as usize / item_size).min(MAX_CORES);
            if count == 0 {
                return Vec::new();
            }

            let mut previous = match PREV_CORES.lock() {
                Ok(guard) => guard,
                Err(poisoned) => poisoned.into_inner(),
            };
            if previous.len() != count {
                *previous = vec![(0, 0); count];
            }

            let mut loads = Vec::with_capacity(count);
            let mut all_zero = true;
            for index in 0..count {
                let info = &buffer[index];
                let idle = info.idle_time.max(0) as u64;
                let total = (info.kernel_time.max(0) + info.user_time.max(0)) as u64;
                let (prev_idle, prev_total) = previous[index];
                previous[index] = (idle, total);

                if prev_total == 0 || total <= prev_total {
                    loads.push(0.0);
                    continue;
                }
                all_zero = false;
                let delta_total = (total - prev_total) as f64;
                let delta_idle = idle.saturating_sub(prev_idle) as f64;
                let busy = (delta_total - delta_idle).max(0.0);
                loads.push(((busy / delta_total) * 100.0).clamp(0.0, 100.0));
            }

            if all_zero {
                return Vec::new();
            }
            loads
        }
    }

    /// Temperatura da zona térmica ACPI (em °C). Devolve -1.0 quando o
    /// firmware/máquina não expõe a zona ou o contador não está disponível.
    pub fn get_cpu_temp_c() -> f64 {
        unsafe {
            let mut query: isize = 0;
            if PdhOpenQueryW(ptr::null(), 0, &mut query) != 0 || query == 0 {
                return -1.0;
            }

            let mut temperature = -1.0;
            let path: Vec<u16> = "\\Thermal Zone Information(*)\\High Precision Temperature\0"
                .encode_utf16()
                .collect();
            let mut counter: isize = 0;
            if PdhAddEnglishCounterW(query, path.as_ptr(), 0, &mut counter) == 0
                && counter != 0
                && PdhCollectQueryData(query) == 0
            {
                let mut size: u32 = 0;
                let mut items: u32 = 0;
                let probe = PdhGetFormattedCounterArrayW(
                    counter,
                    PDH_FMT_DOUBLE,
                    &mut size,
                    &mut items,
                    ptr::null_mut(),
                );
                if probe == PDH_MORE_DATA && size > 0 {
                    let mut buffer = vec![0u8; size as usize];
                    let mut filled: u32 = size;
                    let mut count: u32 = 0;
                    let read = PdhGetFormattedCounterArrayW(
                        counter,
                        PDH_FMT_DOUBLE,
                        &mut filled,
                        &mut count,
                        buffer.as_mut_ptr(),
                    );
                    if read == 0 && count > 0 {
                        let values = std::slice::from_raw_parts(
                            buffer.as_ptr() as *const PdhFmtCounterValueItemW,
                            count as usize,
                        );
                        let mut max_celsius = f64::MIN;
                        for item in values {
                            if item.value.status != PDH_CSTATUS_VALID_DATA
                                || !item.value.double_value.is_finite()
                            {
                                continue;
                            }
                            // O contador expõe décimos de Kelvin.
                            let celsius = item.value.double_value / 10.0 - 273.15;
                            if (-30.0..=150.0).contains(&celsius) && celsius > max_celsius {
                                max_celsius = celsius;
                            }
                        }
                        if max_celsius > f64::MIN {
                            temperature = (max_celsius * 10.0).round() / 10.0;
                        }
                    }
                }
            }

            PdhCloseQuery(query);
            temperature
        }
    }

    pub fn get_memory_info() -> Option<(u64, u64, u32)> {
        unsafe {
            let mut status = zeroed::<MemoryStatusEx>();
            status.dw_length = std::mem::size_of::<MemoryStatusEx>() as u32;
            if GlobalMemoryStatusEx(&mut status) == 0 {
                return None;
            }
            Some((status.ull_total_phys, status.ull_avail_phys, status.dw_memory_load))
        }
    }
}

/// Mede o uso instantâneo de CPU no Windows (0.0 a 100.0) via Win32 GetSystemTimes.
#[no_mangle]
pub extern "C" fn bmb_sys_cpu_usage() -> f64 {
    #[cfg(target_os = "windows")]
    {
        windows_telemetry::get_cpu_percent()
    }
    #[cfg(not(target_os = "windows"))]
    {
        0.0
    }
}

/// Retorna status de memória RAM no Windows em JSON:
/// `{"total_bytes": u64, "available_bytes": u64, "used_bytes": u64, "load_percent": u32}`
#[no_mangle]
pub extern "C" fn bmb_sys_memory_info() -> *mut c_char {
    #[cfg(target_os = "windows")]
    {
        if let Some((total, avail, load)) = windows_telemetry::get_memory_info() {
            let used = total.saturating_sub(avail);
            return to_c_string(format!(
                "{{\"total_bytes\":{},\"available_bytes\":{},\"used_bytes\":{},\"load_percent\":{}}}",
                total, avail, used, load
            ));
        }
    }
    to_c_string("{\"total_bytes\":0,\"available_bytes\":0,\"used_bytes\":0,\"load_percent\":0}".to_string())
}

/// Carga instantânea por núcleo lógico da CPU (Windows via NtQuerySystemInformation).
///
/// JSON: `{"core_count": u32, "loads": [f64, ...]}` (0.0 a 100.0 por núcleo).
/// Fora do Windows devolve `core_count: 0` — as demais plataformas leem o
/// equivalente pelo sistema nativo delas.
#[no_mangle]
pub extern "C" fn bmb_sys_cpu_per_core() -> *mut c_char {
    #[cfg(target_os = "windows")]
    {
        let loads = windows_telemetry::get_cpu_per_core();
        if !loads.is_empty() {
            let list = loads
                .iter()
                .map(|v| format!("{:.1}", v))
                .collect::<Vec<_>>()
                .join(",");
            return to_c_string(format!(
                "{{\"core_count\":{},\"loads\":[{}]}}",
                loads.len(),
                list
            ));
        }
    }
    to_c_string("{\"core_count\":0,\"loads\":[]}".to_string())
}

/// Temperatura da zona térmica ACPI da CPU em °C (Windows). Devolve -1.0
/// quando o firmware não expõe a zona térmica.
#[no_mangle]
pub extern "C" fn bmb_sys_cpu_temp_c() -> f64 {
    #[cfg(target_os = "windows")]
    {
        return windows_telemetry::get_cpu_temp_c();
    }
    #[cfg(not(target_os = "windows"))]
    {
        -1.0
    }
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

    #[test]
    #[cfg(target_os = "windows")]
    fn windows_telemetry_returns_valid_data() {
        let cpu = bmb_sys_cpu_usage();
        assert!(cpu >= 0.0 && cpu <= 100.0);

        let mem_json = unsafe { take(bmb_sys_memory_info()) };
        assert!(mem_json.contains("total_bytes"));
        assert!(mem_json.contains("available_bytes"));
        assert!(mem_json.contains("used_bytes"));
    }

    #[test]
    fn cpu_per_core_json_shape() {
        let json = unsafe { take(bmb_sys_cpu_per_core()) };
        assert!(json.starts_with("{\"core_count\":"), "json inesperado: {json}");
        assert!(json.contains("\"loads\":["));
        assert!(json.ends_with("]}"));
    }

    #[test]
    fn cpu_temp_is_sane_or_unavailable() {
        let temp = bmb_sys_cpu_temp_c();
        // -1.0 = sem zona térmica exposta; fora disso precisa ser plausível.
        assert!(
            temp == -1.0 || (-30.0..150.0).contains(&temp),
            "temperatura implausível: {temp}"
        );
    }

    #[test]
    #[cfg(target_os = "windows")]
    fn windows_per_core_returns_all_cores() {
        // A primeira leitura só registra a amostra; a segunda calcula a taxa.
        let _ = unsafe { take(bmb_sys_cpu_per_core()) };
        std::thread::sleep(std::time::Duration::from_millis(200));
        let json = unsafe { take(bmb_sys_cpu_per_core()) };
        assert!(
            !json.contains("\"loads\":[]"),
            "esperava cargas por núcleo: {json}"
        );

        let core_count: usize = json
            .split("\"core_count\":")
            .nth(1)
            .and_then(|rest| rest.split(',').next())
            .and_then(|value| value.trim().parse().ok())
            .expect("core_count ausente");
        let loads_raw = json
            .split("\"loads\":[")
            .nth(1)
            .and_then(|rest| rest.strip_suffix("]}"))
            .expect("loads ausente");
        let loads: Vec<f64> = loads_raw
            .split(',')
            .filter(|part| !part.trim().is_empty())
            .filter_map(|part| part.trim().parse().ok())
            .collect();

        assert!(core_count >= 2, "core_count suspeito: {core_count}");
        assert_eq!(loads.len(), core_count, "cargas fora de sincronia: {json}");
        assert!(
            loads.iter().all(|v| (0.0..=100.0).contains(v)),
            "carga fora de faixa: {json}"
        );
    }
}
