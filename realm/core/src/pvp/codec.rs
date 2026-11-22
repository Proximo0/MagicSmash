//! The PvP block of the state bytes (job R3): written only when something is in it (`Pvp::is_empty`), read back
//! whole or not at all.

use super::{DUEL_OVER, Duel, NOBODY, Pvp, War};

impl Pvp {
    pub(crate) fn write(&self, w: &mut Vec<u8>) {
        w.push(BLOCK_TAG);
        w.push(self.marked_realm as u8);
        w.push(self.wars.len() as u8);
        for war in &self.wars {
            w.extend_from_slice(&war.id.to_le_bytes());
            w.extend_from_slice(&war.guilds[0].to_le_bytes());
            w.extend_from_slice(&war.guilds[1].to_le_bytes());
            w.extend_from_slice(&war.tide.to_le_bytes());
            w.extend_from_slice(&war.held[0].to_le_bytes());
            w.extend_from_slice(&war.held[1].to_le_bytes());
            w.push(war.on as u8);
        }
        match &self.duel {
            Some(d) => {
                w.push(1);
                w.extend_from_slice(&d.heroes[0].to_le_bytes());
                w.extend_from_slice(&d.heroes[1].to_le_bytes());
                w.extend_from_slice(&d.started.to_le_bytes());
                w.push(d.state);
            }
            None => w.push(0),
        }
        let tags: Vec<(usize, u64)> = self.guild.iter().copied().enumerate().filter(|&(_, g)| g != 0).collect();
        w.extend_from_slice(&(tags.len() as u16).to_le_bytes());
        for (i, g) in tags {
            w.extend_from_slice(&(i as u16).to_le_bytes());
            w.extend_from_slice(&g.to_le_bytes());
        }
        let downs: Vec<(usize, u16)> = self.downer.iter().copied().enumerate().filter(|&(_, d)| d != NOBODY).collect();
        w.extend_from_slice(&(downs.len() as u16).to_le_bytes());
        for (i, d) in downs {
            w.extend_from_slice(&(i as u16).to_le_bytes());
            w.extend_from_slice(&d.to_le_bytes());
        }
    }

    /// Reads the block `write` wrote from `b[*at..]`; None when it is not whole.
    pub(crate) fn read(b: &[u8], at: &mut usize, heroes: usize) -> Option<Pvp> {
        let mut take = |n: usize| -> Option<&[u8]> {
            let s = b.get(*at..*at + n)?;
            *at += n;
            Some(s)
        };
        if take(1)?[0] != BLOCK_TAG {
            return None;
        }
        let mut p = Pvp { marked_realm: flag(take(1)?[0])?, ..Pvp::default() };
        let n = take(1)?[0];
        for _ in 0..n {
            let id = u64::from_le_bytes(take(8)?.try_into().ok()?);
            let g0 = u64::from_le_bytes(take(8)?.try_into().ok()?);
            let g1 = u64::from_le_bytes(take(8)?.try_into().ok()?);
            let tide = u32::from_le_bytes(take(4)?.try_into().ok()?);
            let h0 = u32::from_le_bytes(take(4)?.try_into().ok()?);
            let h1 = u32::from_le_bytes(take(4)?.try_into().ok()?);
            let on = flag(take(1)?[0])?;
            p.wars.push(War { id, guilds: [g0, g1], tide, held: [h0, h1], on });
        }
        if flag(take(1)?[0])? {
            let a = u16::from_le_bytes(take(2)?.try_into().ok()?);
            let c = u16::from_le_bytes(take(2)?.try_into().ok()?);
            let started = u32::from_le_bytes(take(4)?.try_into().ok()?);
            let state = take(1)?[0];
            if state > DUEL_OVER {
                return None;
            }
            p.duel = Some(Duel { heroes: [a, c], started, state });
        }
        p.guild = vec![0; heroes];
        let n = u16::from_le_bytes(take(2)?.try_into().ok()?);
        for _ in 0..n {
            let i = u16::from_le_bytes(take(2)?.try_into().ok()?) as usize;
            let g = u64::from_le_bytes(take(8)?.try_into().ok()?);
            *p.guild.get_mut(i)? = g;
        }
        p.downer = vec![NOBODY; heroes];
        let n = u16::from_le_bytes(take(2)?.try_into().ok()?);
        for _ in 0..n {
            let i = u16::from_le_bytes(take(2)?.try_into().ok()?) as usize;
            let d = u16::from_le_bytes(take(2)?.try_into().ok()?);
            *p.downer.get_mut(i)? = d;
        }
        Some(p)
    }
}

/// The first byte of the PvP block.
const BLOCK_TAG: u8 = 0x50;

fn flag(b: u8) -> Option<bool> {
    match b {
        0 => Some(false),
        1 => Some(true),
        _ => None,
    }
}
