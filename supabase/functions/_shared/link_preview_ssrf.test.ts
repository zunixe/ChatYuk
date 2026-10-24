import { assertEquals, assert } from 'https://deno.land/std/assert/mod.ts';
import {
  assertSafeUrl,
  isBlockedHostname,
  isBlockedIp,
} from './link_preview.ts';

// ── SSRF guard (REVIEW_2026-10-24 SEC-03) ───────────────────────────────────
// Dulu validasi hanya `^https?://` + panjang, redirect diikuti bebas → user
// login bisa menyuruh server fetch IP internal / cloud metadata lalu membaca
// og:*/<title>-nya (server jadi proxy pemindai). Test ini mengunci guard.

Deno.test('isBlockedIp: rentang privat/loopback/link-local/metadata', () => {
  for (const ip of [
    '127.0.0.1', '127.1.2.3', '10.0.0.1', '10.255.255.255',
    '172.16.0.1', '172.31.255.254', '192.168.1.1',
    '169.254.169.254', // AWS/GCP metadata
    '100.64.0.1', // CGNAT
    '0.0.0.0', '224.0.0.1', '255.255.255.255',
    '::1', '::', 'fc00::1', 'fd12:3456::1', 'fe80::1',
    '::ffff:127.0.0.1', '::ffff:10.1.1.1',
  ]) {
    assert(isBlockedIp(ip), `harus ditolak: ${ip}`);
  }
});

Deno.test('isBlockedIp: IP publik diizinkan', () => {
  for (const ip of ['8.8.8.8', '1.1.1.1', '142.250.4.100', '2606:4700::1111']) {
    assertEquals(isBlockedIp(ip), false, `harus diizinkan: ${ip}`);
  }
});

Deno.test('isBlockedHostname: localhost/.internal/.local + IP literal privat', () => {
  for (const h of [
    'localhost', 'LOCALHOST.', 'metadata.google.internal',
    'kubernetes.default', 'db.internal', 'printer.local',
    'api.localhost', '127.0.0.1', '10.1.2.3', '169.254.169.254',
  ]) {
    assert(isBlockedHostname(h), `harus ditolak: ${h}`);
  }
  for (const h of ['example.com', 'youtube.com', 'sub.domain.co.id']) {
    assertEquals(isBlockedHostname(h), false, `harus diizinkan: ${h}`);
  }
});

Deno.test('assertSafeUrl: tolak skema/kredensial/IP privat', async () => {
  for (const u of [
    'file:///etc/passwd',
    'ftp://example.com/x',
    'javascript:alert(1)',
    'data:text/html,<h1>x</h1>',
    'http://127.0.0.1/admin',
    'http://169.254.169.254/latest/meta-data/',
    'http://localhost:5432/',
    'http://user:pass@example.com/',
    'http://db.internal/',
  ]) {
    assertEquals(await assertSafeUrl(u), null, `harus ditolak: ${u}`);
  }
});

Deno.test('assertSafeUrl: izinkan URL publik normal', async () => {
  for (const u of ['https://example.com/a', 'http://sub.example.co.id/b?c=1']) {
    const parsed = await assertSafeUrl(u);
    assert(parsed !== null, `harus diizinkan: ${u}`);
  }
});
