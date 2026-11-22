//! The report table of the bench and the server: one row per window of ticks.

use crate::sim::{COL_NAMES, C_TOTAL, NCOL};
use crate::stats::{dist, kb, Dist};
use realm_core::Field;

/// One report window's numbers.
#[derive(Default)]
pub struct Window {
    pub ticks: Vec<[f64; NCOL]>,
    pub a0: Vec<f64>,
    pub a1: Vec<f64>,
    pub b: Vec<f64>,
    pub view_mon: Vec<f64>,
    pub view_ply: Vec<f64>,
    pub follow_ms: Vec<f64>,
    pub hash_ok: u64,
    pub hash_bad: u64,
}

pub fn header() {
    println!(
        "{:>13} {:>3} {:>6} | {:>13} | {} | {:>13} {:>13} {:>13} | {:>9} {:>9} | {:>7} | {:>11} | {}",
        "players x mon", "thr", "tick",
        "tick ms m/p99",
        COL_NAMES[..C_TOTAL].iter().map(|n| format!("{n:>11}")).collect::<Vec<_>>().join(" "),
        "A0 B/s m/p99", "A1 B/s m/p99", "B B/s m/p99",
        "mon view", "ply view", "join B", "follow ms", "hash"
    );
}

pub fn md(d: Dist) -> String {
    format!("{:.2}/{:.2}", d.mean, d.p99)
}

pub fn report(f: &Field, threads: usize, w: &Window, join_bytes: usize) {
    let col = |c: usize| dist(&w.ticks.iter().map(|r| r[c]).collect::<Vec<_>>());
    let bw = |v: &[f64]| {
        let d = dist(v);
        if d.n == 0 { "-".to_string() } else { format!("{}/{}", kb(d.mean), kb(d.p99)) }
    };
    let vm = dist(&w.view_mon);
    let vp = dist(&w.view_ply);
    let fl = dist(&w.follow_ms);
    println!(
        "{:>13} {:>3} {:>6} | {:>13} | {} | {:>13} {:>13} {:>13} | {:>9} {:>9} | {:>7} | {:>11} | {}",
        format!("{}x{}", f.player_count(), f.monster_count()),
        threads,
        f.tick(),
        md(col(C_TOTAL)),
        (0..C_TOTAL).map(|c| format!("{:>11}", md(col(c)))).collect::<Vec<_>>().join(" "),
        bw(&w.a0),
        bw(&w.a1),
        bw(&w.b),
        if vm.n == 0 { "-".into() } else { format!("{:.0}/{:.0}", vm.mean, vm.p99) },
        if vp.n == 0 { "-".into() } else { format!("{:.0}/{:.0}", vp.mean, vp.p99) },
        kb(join_bytes as f64),
        if fl.n == 0 { "-".into() } else { md(fl) },
        if w.hash_ok + w.hash_bad == 0 { "-".into() } else if w.hash_bad == 0 { format!("ok {}", w.hash_ok) } else { format!("BAD {}/{}", w.hash_bad, w.hash_ok + w.hash_bad) }
    );
}
