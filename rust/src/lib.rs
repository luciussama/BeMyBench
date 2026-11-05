//! BMyBench (Be My Bench) — benchmark core em Rust.
//!
//! Objetivo: score próprio de CPU e Memória, consistente entre macOS, Windows,
//! Linux e Android. A UI (Flutter) chama estas funções via flutter_rust_bridge.
//!
//! MVP planeja:
//! - `cpu_single_core()` / `cpu_multi_core()` — hash/física/render, operações por segundo
//! - `memory_benchmark()` — GB/s leitura/escrita + latência
//! - `disk_benchmark()` — MB/s sequencial
//!
//! Nenhuma marca Geekbench/Cinebench é clonada — score é metodologia própria.

/// Stub MVP: será substituído pela implementação real (rayon + loops de workload).
pub fn cpu_single_core_placeholder() -> String {
    "TODO: cpu_single_core".to_string()
}

pub fn memory_benchmark_placeholder() -> String {
    "TODO: memory_benchmark".to_string()
}

pub fn disk_benchmark_placeholder() -> String {
    "TODO: disk_benchmark".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn placeholders_return_todo() {
        assert!(cpu_single_core_placeholder().contains("TODO"));
        assert!(memory_benchmark_placeholder().contains("TODO"));
        assert!(disk_benchmark_placeholder().contains("TODO"));
    }
}
