//! SipHash-2-4 (Aumasson and Bernstein, 2012): the field wire's MAC, keyed by a ticket's 128-bit key. Here
//! because `realm-server` stays std only (it builds with no network, and the Godot module uses it); the gateway and
//! the native module use this same function. A 64-bit tag is what SipHash was made for: a short-input MAC where a
//! forger gets one try per datagram (`docs/realm/wire.md`, "Transport security").

fn round(v: &mut [u64; 4]) {
    v[0] = v[0].wrapping_add(v[1]);
    v[1] = v[1].rotate_left(13) ^ v[0];
    v[0] = v[0].rotate_left(32);
    v[2] = v[2].wrapping_add(v[3]);
    v[3] = v[3].rotate_left(16) ^ v[2];
    v[0] = v[0].wrapping_add(v[3]);
    v[3] = v[3].rotate_left(21) ^ v[0];
    v[2] = v[2].wrapping_add(v[1]);
    v[1] = v[1].rotate_left(17) ^ v[2];
    v[2] = v[2].rotate_left(32);
}

/// SipHash-2-4 of `data` under `key`.
pub fn siphash24(key: &[u8; 16], data: &[u8]) -> u64 {
    let k0 = u64::from_le_bytes(key[..8].try_into().unwrap_or([0; 8]));
    let k1 = u64::from_le_bytes(key[8..].try_into().unwrap_or([0; 8]));
    let mut v = [k0 ^ 0x736f_6d65_7073_6575, k1 ^ 0x646f_7261_6e64_6f6d, k0 ^ 0x6c79_6765_6e65_7261, k1 ^ 0x7465_6462_7974_6573];
    let mut chunks = data.chunks_exact(8);
    for c in &mut chunks {
        let m = u64::from_le_bytes(c.try_into().unwrap_or([0; 8]));
        v[3] ^= m;
        round(&mut v);
        round(&mut v);
        v[0] ^= m;
    }
    let mut last = [0u8; 8];
    let rest = chunks.remainder();
    last[..rest.len()].copy_from_slice(rest);
    last[7] = data.len() as u8;
    let m = u64::from_le_bytes(last);
    v[3] ^= m;
    round(&mut v);
    round(&mut v);
    v[0] ^= m;
    v[2] ^= 0xff;
    for _ in 0..4 {
        round(&mut v);
    }
    v[0] ^ v[1] ^ v[2] ^ v[3]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_reference_vectors_and_stds_siphasher_agree() {
        // The reference implementation's vectors (key 00..0f, message 00..n-1), and the paper's 15-byte example.
        let key: [u8; 16] = std::array::from_fn(|i| i as u8);
        let msg: Vec<u8> = (0..64).collect();
        let want = [(0, 0x726f_db47_dd0e_0e31u64), (1, 0x74f8_39c5_93dc_67fd), (2, 0x0d6c_8009_d9a9_4f5a), (3, 0x8567_6696_d7fb_7e2d), (15, 0xa129_ca61_49be_45e5)];
        for (n, v) in want {
            assert_eq!(siphash24(&key, &msg[..n]), v, "length {n}");
        }
        // Every length 0..64 (each tail and block boundary) against the standard library's SipHash-2-4.
        #[allow(deprecated)]
        for n in 0..64 {
            use std::hash::Hasher;
            let mut h = std::hash::SipHasher::new_with_keys(u64::from_le_bytes(key[..8].try_into().unwrap()), u64::from_le_bytes(key[8..].try_into().unwrap()));
            h.write(&msg[..n]);
            assert_eq!(siphash24(&key, &msg[..n]), h.finish(), "length {n}");
        }
    }
}
