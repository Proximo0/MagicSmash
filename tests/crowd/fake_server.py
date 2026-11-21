#!/usr/bin/env python3
"""Fake server for the crowd viewer: speaks protocol A version 0 (docs/realm/crowd_test.md), standard library only.

  python3 tests/crowd/fake_server.py --port=7777 --players=1000 --monsters=20000 --secs=60

One client at a time is enough (several work). A horde closes in on the client, a crowd mills about around it.
Only the monsters near the client are simulated, the rest are only counted."""
import argparse
import math
import random
import select
import socket
import struct
import time

FIELD = 16384
HZ = 20
NEAR_PLAYERS = 200
MAX_CROWD = 1000
MAX_MON = 1500
PART_MAX = 1200
ACTIVE_MON = 2600
SPEED = 60.0
DIRS = {0: (0, 0), 1: (1, 0), 2: (1, 1), 3: (0, 1), 4: (-1, 1), 5: (-1, 0), 6: (-1, -1), 7: (0, -1), 8: (1, -1)}
MON_SPEED = [30, 24, 36, 48, 28, 70, 40, 36]


def varint(v):
    out = bytearray()
    while v >= 0x80:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    out.append(v)
    return bytes(out)


class Client:
    def __init__(self, addr, pid, cls, race):
        self.addr, self.pid, self.cls, self.race = addr, pid, cls, race
        self.x = self.y = FIELD / 2.0
        self.move, self.skill, self.zoom = 0, False, 1
        self.last_seen = time.time()
        self.hurt_until = 0
        self.face_left = False
        self.moving = False


class Sim:
    def __init__(self, n_players, n_monsters, seed=7):
        self.rng = random.Random(seed)
        self.n_players, self.n_monsters = n_players, n_monsters
        self.tick = 0
        self.next_mon_id = 1
        self.mons = []  # [id, x, y, kind, hp8, elite, hurt_until, stop distance]
        self.crowd = []  # [id, x, y, kind, vx, vy, face_left]
        for i in range(max(0, n_players - 1)):
            a = self.rng.random() * math.tau
            r = abs(self.rng.gauss(0, 700))
            self.crowd.append([100 + i, FIELD / 2 + math.cos(a) * r, FIELD / 2 + math.sin(a) * r,
                               self.rng.randrange(5) | (self.rng.randrange(4) << 3), 0.0, 0.0, False])
        self.active_target = min(n_monsters, ACTIVE_MON)

    def spawn_mon(self, cx, cy):
        a = self.rng.random() * math.tau
        r = self.rng.uniform(450, 1500)
        x = min(FIELD - 1, max(0, cx + math.cos(a) * r))
        y = min(FIELD - 1, max(0, cy + math.sin(a) * r))
        m = [self.next_mon_id, x, y, self.rng.randrange(8), 8, 1 if self.rng.random() < 0.03 else 0, 0, self.rng.uniform(25, 420)]
        self.next_mon_id += 1
        return m

    def step(self, clients, dt):
        self.tick += int(dt * HZ)
        now = time.time()
        for c in clients:
            dx, dy = DIRS[c.move]
            n = math.hypot(dx, dy) or 1
            c.x = min(FIELD - 1, max(0, c.x + dx / n * SPEED * dt))
            c.y = min(FIELD - 1, max(0, c.y + dy / n * SPEED * dt))
            c.moving = c.move != 0
            if dx:
                c.face_left = dx < 0
        if not clients:
            return
        c0 = clients[0]
        while len(self.mons) < self.active_target:
            self.mons.append(self.spawn_mon(c0.x, c0.y))
        keep = []
        for m in self.mons:
            dx, dy = c0.x - m[1], c0.y - m[2]
            d = math.hypot(dx, dy)
            if d > 1800:
                keep.append(self.spawn_mon(c0.x, c0.y))
                continue
            sp = MON_SPEED[m[3]] * dt
            if d > m[7]:  # a horde closing in, each one stopping at its own distance and milling about
                m[1] += dx / d * sp
                m[2] += dy / d * sp
            m[1] += self.rng.uniform(-2.0, 2.0)
            m[2] += self.rng.uniform(-2.0, 2.0)
            if d < 90 and self.rng.random() < 0.03:  # the player's attack: a monster dies, another comes
                keep.append(self.spawn_mon(c0.x, c0.y))
                continue
            if self.rng.random() < 0.01:
                m[6] = now + 0.15
            keep.append(m)
        self.mons = keep
        for p in self.crowd:  # mill about, drift toward the client's area
            if self.rng.random() < 0.15:
                a = self.rng.random() * math.tau
                p[4], p[5] = math.cos(a) * SPEED, math.sin(a) * SPEED
            gx, gy = c0.x - p[1], c0.y - p[2]
            gd = math.hypot(gx, gy)
            if gd > 1100:
                p[4] += gx / gd * 40
                p[5] += gy / gd * 40
            p[1] = min(FIELD - 1, max(0, p[1] + p[4] * dt))
            p[2] = min(FIELD - 1, max(0, p[2] + p[5] * dt))
            if p[4]:
                p[6] = p[4] < 0

    def snapshot_parts(self, c, tick_ms100):
        half_w = 240 * c.zoom + 64
        half_h = 135 * c.zoom + 64
        ox = int(min(max(c.x - half_w, 0), FIELD - 2 * half_w))
        oy = int(min(max(c.y - half_h, 0), FIELD - 2 * half_h))
        w, h = 2 * half_w, 2 * half_h
        now = time.time()
        # players inside the box, nearest first
        near = []
        for p in self.crowd:
            if ox <= p[1] < ox + w and oy <= p[2] < oy + h:
                near.append(((p[1] - c.x) ** 2 + (p[2] - c.y) ** 2, p))
        near.sort(key=lambda t: t[0])
        players = [t[1] for t in near[:NEAR_PLAYERS]]
        crowd = [t[1] for t in near[NEAR_PLAYERS:NEAR_PLAYERS + MAX_CROWD]]
        mons = []
        for m in self.mons:
            if ox <= m[1] < ox + w and oy <= m[2] < oy + h:
                mons.append(((m[1] - c.x) ** 2 + (m[2] - c.y) ** 2, m))
        mons.sort(key=lambda t: t[0])
        mons = sorted((t[1] for t in mons[:MAX_MON]), key=lambda m: m[0])

        parts = []  # each [players, crowd, monsters, size]
        cur = [[], [], [], 7 + 26 + 6]

        def room(extra):
            nonlocal cur
            if cur[3] + extra > PART_MAX:
                parts.append(cur)
                cur = [[], [], [], 7 + 6]
        for p in players:
            room(8)
            cur[0].append(p)
            cur[3] += 8
        for p in crowd:
            room(4)
            cur[1].append(p)
            cur[3] += 4
        last = 0
        for m in mons:
            g = len(varint(m[0] - last)) + 4
            if cur[3] + g > PART_MAX:
                parts.append(cur)
                cur = [[], [], [], 7 + 6]
                last = 0
                g = len(varint(m[0])) + 4
            cur[2].append(m)
            cur[3] += g
            last = m[0]
        parts.append(cur)
        out = []
        for i, pt in enumerate(parts):
            b = bytearray(struct.pack("<BIBB", 0x82, self.tick, i, len(parts)))
            if i == 0:
                b += struct.pack("<iiHHHHIIH", ox, oy, int(c.x - ox), int(c.y - oy), 100, 1,
                                 self.n_players, self.n_monsters, tick_ms100)
            b += struct.pack("<HHH", len(pt[0]), len(pt[1]), len(pt[2]))
            for p in pt[0]:
                fl = (1 if p[6] else 0) | (2 if (abs(p[4]) + abs(p[5])) > 1 else 0) | (4 if self.rng.random() < 0.02 else 0)
                b += struct.pack("<HHHBB", p[0] & 0xFFFF, int(p[1] - ox), int(p[2] - oy), p[3], fl)
            for p in pt[1]:
                b += struct.pack("<HH", int(p[1] - ox), int(p[2] - oy))
            last = 0
            for m in pt[2]:
                b += varint(m[0] - last)
                last = m[0]
                hurt = 1 if m[6] > now else 0
                v = (int(m[1] - ox) & 0xFFF) | ((int(m[2] - oy) & 0x7FF) << 12) | (hurt << 23)
                b += bytes([v & 255, (v >> 8) & 255, v >> 16, (m[3] & 7) | ((m[4] & 7) << 3) | (m[5] << 6)])
            out.append(bytes(b))
        return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=7777)
    ap.add_argument("--players", type=int, default=1000)
    ap.add_argument("--monsters", type=int, default=20000)
    ap.add_argument("--secs", type=float, default=0, help="quit after this long (0 = until killed)")
    ap.add_argument("--shuffle", action="store_true", help="send the parts of a snapshot in random order")
    a = ap.parse_args()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", a.port))
    sim = Sim(a.players, a.monsters)
    clients = {}
    next_id = 1
    t0 = time.time()
    nxt = t0
    snaps = 0
    while a.secs <= 0 or time.time() - t0 < a.secs:
        wait = max(0.0, nxt - time.time())
        r, _, _ = select.select([sock], [], [], wait)
        while r:
            data, addr = sock.recvfrom(2048)
            if data[:1] == b"\x01" and len(data) >= 7:
                if addr not in clients:
                    clients[addr] = Client(addr, next_id, data[5], data[6])
                    next_id += 1
                c = clients[addr]
                sock.sendto(struct.pack("<BIIHII", 0x81, c.pid, sim.tick, HZ, FIELD, FIELD), addr)
            elif data[:1] == b"\x02" and len(data) >= 7 and addr in clients:
                c = clients[addr]
                c.move, c.skill, c.zoom = data[5] & 0x7F, bool(data[5] & 0x80), data[6] if data[6] in (1, 2, 4) else 1
                c.last_seen = time.time()
            elif data[:1] == b"\x03":
                clients.pop(addr, None)
            r, _, _ = select.select([sock], [], [], 0)
        now = time.time()
        if now >= nxt:
            nxt += 1.0 / 10  # one snapshot (every 2nd tick of 20 Hz)
            if nxt < now - 1:
                nxt = now
            for addr in [k for k, c in clients.items() if now - c.last_seen > 10]:
                del clients[addr]
            s = time.perf_counter()
            sim.step(list(clients.values()), 0.1)
            tick_ms = int((time.perf_counter() - s) * 100000)
            snaps += 1
            for c in clients.values():
                parts = sim.snapshot_parts(c, min(tick_ms, 65535))
                if a.shuffle:
                    random.shuffle(parts)
                for p in parts:
                    sock.sendto(p, c.addr)
    sock.close()


if __name__ == "__main__":
    main()
