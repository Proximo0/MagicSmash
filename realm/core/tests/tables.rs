//! The tables against the contract (`docs/realm/rules.md`): every monster row, card name, class row and field row
//! is read from the contract's own tables, so a change to one side fails here. Plus the rules behind the rows
//! that no other test reaches: level scaling, ELITES and CHAMPIONS, births only of the field's kinds.
mod common;
use common::*;

fn contract() -> String {
    let p = concat!(env!("CARGO_MANIFEST_DIR"), "/../../docs/realm/rules.md");
    std::fs::read_to_string(p).expect("docs/realm/rules.md")
}

/// The rows of the markdown table whose header starts with `head`, as trimmed cells.
fn table(doc: &str, head: &str) -> Vec<Vec<String>> {
    let lines: Vec<&str> = doc.lines().collect();
    let at = lines.iter().position(|l| l.starts_with(head)).unwrap_or_else(|| panic!("no table {head}"));
    lines[at + 2..]
        .iter()
        .take_while(|l| l.starts_with('|'))
        .map(|l| l.trim_matches('|').split('|').map(|c| c.trim().to_string()).collect())
        .collect()
}

const FIELD_NAMES: [&str; 6] = ["Fool's Road", "Hanged Wood", "Moon Marsh", "Hermit's Peaks", "The Tower", "World's Edge"];

#[test]
fn every_monster_row_matches_the_contract() {
    let rows = table(&contract(), "| Field | Kind | Behaviour");
    assert_eq!(rows.len(), KINDS.len());
    let words = [
        ("walker", WALKER),
        ("swarm", SWARM),
        ("runner", RUNNER),
        ("brute", BRUTE),
        ("shielded", SHIELDED),
        ("burster", BURSTER),
        ("splitter", SPLITTER),
        ("spitter", SPITTER),
        ("lobber", LOBBER),
        ("leaper", LEAPER),
        ("howler", HOWLER),
        ("mender", MENDER),
        ("wailer", WAILER),
        ("drainer", DRAINER),
    ];
    for (r, k) in rows.iter().zip(KINDS.iter()) {
        assert_eq!(r[1], k.name);
        assert_eq!(FIELD_NAMES.iter().position(|&n| n == r[0]).unwrap() as u8, k.field, "{}", k.name);
        let mut beh = 0;
        for part in r[2].split(',') {
            let w = part.trim().split(' ').next().unwrap();
            if let Some(&(_, b)) = words.iter().find(|(n, _)| *n == w) {
                beh |= b;
            }
        }
        assert_eq!(beh, k.beh, "{}: {}", k.name, r[2]);
        let n: Vec<u32> = r[3..7].iter().map(|c| c.parse().unwrap()).collect();
        assert_eq!(n, vec![k.speed, k.health, k.damage, k.xp], "{}", k.name);
        let clutch = if r[2].contains("clutches of 4") { 4 } else if k.beh & SWARM != 0 { SWARM_CLUTCH } else { 1 };
        assert_eq!(k.clutch, clutch, "{}", k.name);
        assert_eq!(k.hits, if r[2].contains("twice as often") { 2 } else { 1 }, "{}", k.name);
        if let Some(into) = r[2].split("splitter into ").nth(1) {
            let child = KINDS[k.split as usize].name;
            // Plurals in the contract: men, legionaries.
            assert!(into.starts_with(&child[..child.len() - 2]), "{}: splits into {child}, contract {into}", k.name);
        } else {
            assert_eq!(k.split, NO_KIND, "{}", k.name);
        }
    }
    // Each field's kinds are a contiguous run.
    for (f, row) in FIELDS.iter().enumerate() {
        let run = &KINDS[row.first_kind as usize..(row.first_kind + row.kind_count) as usize];
        assert!(run.iter().all(|k| k.field == f as u8));
        assert_eq!(KINDS.iter().filter(|k| k.field == f as u8).count(), row.kind_count as usize);
    }
}

#[test]
fn every_card_name_matches_the_contract() {
    let rows = table(&contract(), "| # | Card |");
    assert_eq!(rows.len(), NCARDS);
    for r in rows {
        let id: usize = r[0].parse().unwrap();
        assert_eq!(CARDS[id].name, r[1]);
    }
}

#[test]
fn every_class_row_matches_the_contract() {
    let rows = table(&contract(), "| Class | Role |");
    assert_eq!(rows.len(), CLASSES.len());
    for (r, c) in rows.iter().zip(CLASSES.iter()) {
        assert_eq!(r[0], c.name);
        let h: Vec<u32> = r[2].replace(['+', ','], " ").split_whitespace().map(|v| v.parse().unwrap()).collect();
        assert_eq!(h, vec![c.health, c.health_per_level], "{}", c.name);
        assert!(r[3].starts_with(c.weapon.name), "{}", c.name);
        assert!(r[3].contains(&format!("{} damage", c.weapon.damage)), "{}", c.name);
        assert!(r[3].contains(&format!("{} ticks", c.weapon.every)), "{}", c.name);
        let threat: Vec<i32> = r[4].split('.').map(|v| v.parse().unwrap()).collect();
        assert_eq!(threat[0] * 10 + threat[1], c.threat, "{}", c.name);
    }
}

#[test]
fn every_field_row_matches_the_contract() {
    let rows = table(&contract(), "| Field | Levels |");
    assert_eq!(rows.len(), FIELDS.len());
    for (r, f) in rows.iter().zip(FIELDS.iter()) {
        assert_eq!(r[0], f.name);
        let l: Vec<u8> = r[1].split(" to ").map(|v| v.parse().unwrap()).collect();
        assert_eq!(l, vec![f.bottom, f.top]);
    }
}

#[test]
fn every_job_row_matches_the_contract() {
    let rows = table(&contract(), "| Job (class) |");
    assert_eq!(rows.len(), JOBS.len());
    for (r, j) in rows.iter().zip(JOBS.iter()) {
        assert!(r[0].starts_with(j.name), "{}", r[0]);
        assert!(r[0].to_uppercase().contains(CLASSES[j.class as usize].name), "{}", r[0]);
        assert!(r[3].starts_with(SKILLS[j.ultimate as usize].name), "{}", r[3]);
        let cd: u32 = r[3].rsplit('(').next().unwrap().trim_end_matches(" s)").parse().unwrap();
        assert_eq!(SKILLS[j.ultimate as usize].cooldown, secs(cd), "{}", j.name);
    }
}

#[test]
fn monster_numbers_grow_18_and_12_percent_a_level() {
    for (i, k) in KINDS.iter().enumerate() {
        let i = i as u8;
        assert_eq!(max_hp(i, 1, 0), k.health);
        assert_eq!(max_hp(i, 11, 0), k.health * (100 + 18 * 10) / 100);
        assert_eq!(max_hp(i, 11, ELITE), k.health * 280 / 100 * 4);
        assert_eq!(max_hp(i, 11, CHAMPION), k.health * 280 / 100 * 25);
        assert_eq!(level_scale(k.damage, 11, POWER_PCT_PER_LEVEL), (k.damage * 220 / 100).max(1));
    }
    let mut f = quiet(0);
    let e = f.place_monster(2, 5, ELITE, FIELD / 2, FIELD / 2).unwrap();
    let c = f.place_monster(2, 5, CHAMPION, FIELD / 2, FIELD / 2).unwrap();
    let n = mon(&mut f, 2, 5, FIELD / 2, FIELD / 2);
    let m = f.monsters();
    assert_eq!((m.xp(e as usize), m.xp(c as usize)), (m.xp(n as usize) * 3, m.xp(n as usize) * 20));
    assert_eq!(m.damage(c as usize), m.damage(n as usize) * 2);
    assert_eq!(m.damage(e as usize), m.damage(n as usize));
}

#[test]
fn births_are_only_the_fields_kinds_with_some_elites() {
    for field in 0..6u8 {
        let mut f = Field::open(field, 11, Config { monsters: 20_000, threads: 2 });
        let mut ids = Vec::new();
        for i in 0..40 {
            ids.push(add(&mut f, &Sheet::bench(1 + i % 5, HUMAN, 60), FIELD / 2 + px(200 * (i as i32 % 8 - 4)), FIELD / 2 + px(5000 + 300 * (i as i32 / 8))));
        }
        for &i in &ids {
            guard(&mut f, i);
        }
        f.step::<u16>(&[]);
        let m = f.monsters();
        let row = &FIELDS[field as usize];
        let mut kinds = vec![0u32; KINDS.len()];
        let mut elites = 0;
        for i in 0..m.len() {
            if m.hp[i] > 0 {
                kinds[m.kind[i] as usize] += 1;
                elites += m.is_elite(i) as u32;
                assert_eq!(KINDS[m.kind[i] as usize].field, field);
                assert!(m.level[i] >= row.bottom && m.level[i] <= row.top);
            }
        }
        let alive: u32 = kinds.iter().sum();
        assert_eq!(alive, f.monster_count());
        assert!(kinds[row.first_kind as usize..(row.first_kind + row.kind_count) as usize].iter().all(|&n| n > 0), "field {field}: {kinds:?}");
        // 1 in 50, give or take.
        assert!(elites * 50 > alive / 3 && elites * 50 < alive * 3, "field {field}: {elites} of {alive}");
    }
}
