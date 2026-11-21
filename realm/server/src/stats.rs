//! Means and 99th percentiles for the report.

#[derive(Clone, Copy, Debug, Default)]
pub struct Dist {
    pub mean: f64,
    pub p99: f64,
    pub max: f64,
    pub n: usize,
}

pub fn dist(v: &[f64]) -> Dist {
    if v.is_empty() {
        return Dist::default();
    }
    let mut s = v.to_vec();
    s.sort_by(|a, b| a.total_cmp(b));
    let k = ((s.len() as f64 * 0.99).ceil() as usize).clamp(1, s.len()) - 1;
    Dist { mean: s.iter().sum::<f64>() / s.len() as f64, p99: s[k], max: s[s.len() - 1], n: s.len() }
}

/// kB with one decimal, or bytes when small.
pub fn kb(b: f64) -> String {
    if b >= 10_000.0 { format!("{:.0}k", b / 1000.0) } else if b >= 1000.0 { format!("{:.1}k", b / 1000.0) } else { format!("{b:.0}") }
}
