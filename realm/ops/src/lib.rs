//! Running the realm (job O1): the hooks the gateway and the field hosts call (`log`, `metrics`, `flood`,
//! `switches`), the watchers (`alarm`, `runtime`), and with the `store` feature the host's own tools
//! (`backup`, `release`, `supervise`). Std only except the store. Nothing here is in the simulation: wall time
//! is fine. Every setting is in `config::SETTINGS`; `docs/realm/ops.md` explains them.

pub mod alarm;
pub mod config;
pub mod flood;
pub mod log;
pub mod metrics;
pub mod runtime;
pub mod switches;
pub mod time;

#[cfg(feature = "store")]
pub mod backup;
#[cfg(feature = "store")]
pub mod release;
#[cfg(feature = "store")]
pub mod supervise;
#[cfg(feature = "store")]
pub mod rehearse;
