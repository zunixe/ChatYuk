-- ============================================================
-- Selaraskan drift: buang overload lama list_posts(4-arg) (samakan PROD)
--
-- Di PROD hanya ada SATU overload: list_posts(text,int,timestamptz,boolean,text)
-- (dikonfirmasi via Management API). Overload 4-arg TANPA p_country sudah
-- dibuang. Di fresh-replay LOKAL, overload 4-arg masih ikut tercipta dari
-- migration lama (mis. 20260817000000_timeline_posts.sql) dan tidak pernah
-- di-drop → memicu PostgREST 203 "Could not choose the best candidate"
-- saat client memanggil tanpa p_country.
--
-- Migration ini menyamakan lokal dengan prod (idempotent).
-- ============================================================

drop function if exists public.list_posts(
  text, integer, timestamp with time zone, boolean
);
