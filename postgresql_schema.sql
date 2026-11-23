-- PostgreSQL schema generated from the uploaded schema listing.
-- Target: vanilla PostgreSQL 13+ (pgcrypto for gen_random_uuid()).
--
-- IMPORTANT:
-- 1) This script creates the schema objects, not a database. Create/select the
--    target database first, then run: psql -d YOUR_DATABASE -f schema.sql
-- 2) If importing into Supabase, do NOT recreate auth.users or the auth schema:
--    Supabase manages them. In that case, remove the auth.users section and
--    its auth-specific indexes/trigger below, and keep the public tables.
-- 3) The source referenced handle_new_user_role(), valid_izin_group(), and
--    valid_izin_declarations(), but did not include their definitions.
--    The trigger and those custom JSON validation constraints are therefore
--    omitted rather than inventing their behavior. The JSONB columns remain.
-- 4) Random UUID defaults were removed from foreign-key columns. Those defaults
--    would generate unrelated IDs and make inserts fail their foreign keys.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS public;

-- ---------------------------------------------------------------------------
-- ENUM TYPES
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typname = 'app_role'
  ) THEN
    CREATE TYPE public.app_role AS ENUM ('user', 'admin');
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- AUTH USERS
-- For Supabase, use the platform-managed auth.users instead of this table.
-- This is a schema-compatible table definition for standalone PostgreSQL;
-- it does not implement authentication, password hashing, or token workflows.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth.users (
  instance_id uuid,
  id uuid NOT NULL,
  aud varchar(255),
  role varchar(255),
  email varchar(255),
  encrypted_password varchar(255),
  email_confirmed_at timestamptz,
  invited_at timestamptz,
  confirmation_token varchar(255),
  confirmation_sent_at timestamptz,
  recovery_token varchar(255),
  recovery_sent_at timestamptz,
  email_change_token_new varchar(255),
  email_change varchar(255),
  email_change_sent_at timestamptz,
  last_sign_in_at timestamptz,
  raw_app_meta_data jsonb,
  raw_user_meta_data jsonb,
  is_super_admin boolean,
  created_at timestamptz,
  updated_at timestamptz,
  phone text DEFAULT NULL,
  phone_confirmed_at timestamptz,
  phone_change text DEFAULT '',
  phone_change_token varchar(255) DEFAULT '',
  phone_change_sent_at timestamptz,
  confirmed_at timestamptz GENERATED ALWAYS AS
    (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
  email_change_token_current varchar(255) DEFAULT '',
  email_change_confirm_status smallint DEFAULT 0,
  banned_until timestamptz,
  reauthentication_token varchar(255) DEFAULT '',
  reauthentication_sent_at timestamptz,
  is_sso_user boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  is_anonymous boolean NOT NULL DEFAULT false,
  CONSTRAINT users_pkey PRIMARY KEY (id),
  CONSTRAINT users_phone_key UNIQUE (phone),
  CONSTRAINT users_email_change_confirm_status_check
    CHECK (email_change_confirm_status BETWEEN 0 AND 2)
);

CREATE INDEX IF NOT EXISTS users_instance_id_idx
  ON auth.users USING btree (instance_id);
CREATE INDEX IF NOT EXISTS users_instance_id_email_idx
  ON auth.users USING btree (instance_id, lower(email::text));
CREATE UNIQUE INDEX IF NOT EXISTS confirmation_token_idx
  ON auth.users USING btree (confirmation_token)
  WHERE confirmation_token::text !~ '^[0-9 ]*$';
CREATE UNIQUE INDEX IF NOT EXISTS recovery_token_idx
  ON auth.users USING btree (recovery_token)
  WHERE recovery_token::text !~ '^[0-9 ]*$';
CREATE UNIQUE INDEX IF NOT EXISTS email_change_token_current_idx
  ON auth.users USING btree (email_change_token_current)
  WHERE email_change_token_current::text !~ '^[0-9 ]*$';
CREATE UNIQUE INDEX IF NOT EXISTS email_change_token_new_idx
  ON auth.users USING btree (email_change_token_new)
  WHERE email_change_token_new::text !~ '^[0-9 ]*$';
CREATE UNIQUE INDEX IF NOT EXISTS reauthentication_token_idx
  ON auth.users USING btree (reauthentication_token)
  WHERE reauthentication_token::text !~ '^[0-9 ]*$';
CREATE UNIQUE INDEX IF NOT EXISTS users_email_partial_key
  ON auth.users USING btree (email)
  WHERE is_sso_user = false;
CREATE INDEX IF NOT EXISTS users_is_anonymous_idx
  ON auth.users USING btree (is_anonymous);
CREATE INDEX IF NOT EXISTS idx_users_email
  ON auth.users USING btree (email);
CREATE INDEX IF NOT EXISTS idx_users_created_at_desc
  ON auth.users USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_last_sign_in_at_desc
  ON auth.users USING btree (last_sign_in_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_name
  ON auth.users USING btree ((raw_user_meta_data ->> 'name'))
  WHERE raw_user_meta_data ->> 'name' IS NOT NULL;

-- ---------------------------------------------------------------------------
-- PUBLIC TABLES
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.members (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  address text,
  agama text,
  bidang text,
  membership_expiry date,
  membership_status boolean,
  nama_club text,
  name text,
  no_kta text,
  no_ktp text,
  pekerjaan text,
  user_id uuid UNIQUE,
  date_created timestamptz DEFAULT now(),
  atlet boolean,
  telepon text,
  CONSTRAINT members_pkey PRIMARY KEY (id),
  CONSTRAINT members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);

CREATE TABLE IF NOT EXISTS public.payment (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  nama text,
  amount bigint,
  kode text,
  period timestamptz,
  member_id uuid,
  CONSTRAINT payment_pkey PRIMARY KEY (id),
  CONSTRAINT payment_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(id)
);

CREATE TABLE IF NOT EXISTS public.senjata (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  name text,
  type text,
  kaliber text,
  no_pas text,
  status_pas boolean,
  no_pabrik text,
  uji_balistik boolean,
  masa_berlaku date,
  member_id uuid,
  CONSTRAINT senjata_pkey PRIMARY KEY (id),
  CONSTRAINT senjata_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(id)
);

CREATE TABLE IF NOT EXISTS public.document_review (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  document text,
  category text,
  owner_id uuid,
  status text,
  CONSTRAINT document_review_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.user_roles (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id uuid NOT NULL,
  role public.app_role NOT NULL DEFAULT 'user'::public.app_role,
  CONSTRAINT user_roles_pkey PRIMARY KEY (id),
  CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);

CREATE TABLE IF NOT EXISTS public.event (
  created_at timestamptz NOT NULL DEFAULT now(),
  title text,
  startdate date,
  poster_id uuid,
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  CONSTRAINT event_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.izin (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  no_dokumen text,
  nama text,
  kategori text,
  pemohon text,
  alamat text,
  tanggal_dari date,
  tanggal_sampai date,
  undangan boolean,
  cap_kabul boolean,
  rekomendasi boolean,
  keterangan text,
  member_id uuid,
  status text DEFAULT 'submitted'
    CHECK (status IS NULL OR status IN
      ('draft', 'submitted', 'under_review', 'approved', 'rejected', 'expired')),
  rombongan jsonb,
  kelengkapan jsonb,
  data_senjata text,
  periode_asli text,
  admin_note text,
  CONSTRAINT izin_pkey PRIMARY KEY (id),
  CONSTRAINT izin_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(id)
);

CREATE TABLE IF NOT EXISTS public.content (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  title text,
  category text,
  ringkasan text,
  CONSTRAINT content_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.member_review (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  member_id uuid,
  status text NOT NULL DEFAULT 'awaiting_payment'
    CHECK (status IN ('awaiting_payment', 'pending_verification', 'completed', 'rejected')),
  active boolean,
  rejection_reason text,
  admin_note text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT member_review_pkey PRIMARY KEY (id),
  CONSTRAINT member_review_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(id),
  CONSTRAINT member_review_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id)
);

CREATE TABLE IF NOT EXISTS public.memberform (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  nama text,
  tanggal_lahir date,
  tempat_lahir text,
  agama text,
  alamat text,
  no_ktp text,
  status_kawin boolean,
  nama_ortu text,
  alamat_ortu text,
  nama_pasangan text,
  nama_anak text,
  pendidikan_terakhir text,
  pekerjaan_terakhir text,
  latihan_di text,
  anggota_club text,
  club_sejak date,
  jabatan_club text,
  perkara_kriminal text,
  anggota_partai text,
  organisasi_lain text,
  CONSTRAINT memberform_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.member_sponsor (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  sponsor_id uuid,
  form_id uuid,
  CONSTRAINT member_sponsor_pkey PRIMARY KEY (id),
  CONSTRAINT sponsorform_sponsor_id_fkey FOREIGN KEY (sponsor_id) REFERENCES public.members(id),
  CONSTRAINT sponsorform_form_id_fkey FOREIGN KEY (form_id) REFERENCES public.memberform(id)
);

CREATE TABLE IF NOT EXISTS public.sponsor_form (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  nama text,
  tanggal_lahir date,
  tempat_lahir text,
  alamat text,
  telepon text,
  pekerjaan text,
  no_kta text,
  club text,
  jabatan_club text,
  CONSTRAINT sponsor_form_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.izin_submission_review (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  izin_id uuid NOT NULL,
  actor_id uuid,
  action text NOT NULL DEFAULT 'submitted',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT izin_submission_review_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.media_file (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  name text,
  url text,
  CONSTRAINT media_file_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ipaymu_test_payments (
  reference_id text NOT NULL
    CHECK (reference_id ~ '^PRBK-TEST-[a-f0-9-]{36}$'),
  transaction_id text NOT NULL UNIQUE,
  qr_url text NOT NULL,
  amount integer NOT NULL CHECK (amount >= 10000 AND amount <= 100000),
  expires_at text,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'paid', 'expired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz,
  CONSTRAINT ipaymu_test_payments_pkey PRIMARY KEY (reference_id)
);

CREATE TABLE IF NOT EXISTS public.registration_qris_payments (
  order_id text NOT NULL
    CHECK (order_id ~ '^PRBK-REG-[a-f0-9-]{36}$'),
  application_id text NOT NULL,
  member_id text NOT NULL,
  reference_id text NOT NULL UNIQUE,
  transaction_id text NOT NULL UNIQUE,
  qr_url text NOT NULL,
  amount integer NOT NULL CHECK (amount = 250000),
  currency text NOT NULL DEFAULT 'IDR' CHECK (currency = 'IDR'),
  expires_at text,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'paid', 'expired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz,
  CONSTRAINT registration_qris_payments_pkey PRIMARY KEY (order_id)
);

CREATE TABLE IF NOT EXISTS public.member_statistics (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  event_count bigint,
  lomba_count bigint,
  medali_emas bigint,
  medali_perak bigint,
  medali_perunggu bigint,
  juri_count bigint,
  admin_count bigint,
  member_id uuid,
  CONSTRAINT member_statistics_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.event_history (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  event_id bigint,
  member_id uuid,
  juri_status boolean,
  admin_status boolean,
  CONSTRAINT event_history_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.klub (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  nama text NOT NULL UNIQUE
    CHECK (length(btrim(nama)) BETWEEN 1 AND 200),
  deskripsi text,
  logo_url text,
  alamat text,
  total_anggota integer NOT NULL DEFAULT 0 CHECK (total_anggota >= 0),
  is_verified boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT klub_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.site_content (
  key text NOT NULL,
  content jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  CONSTRAINT site_content_pkey PRIMARY KEY (key)
);

-- ---------------------------------------------------------------------------
-- Optional FK constraints inferred from column names were NOT added where the
-- uploaded schema did not define them (e.g. event_history.event_id/member_id,
-- member_statistics.member_id, izin_submission_review.izin_id/actor_id,
-- document_review.owner_id, site_content.updated_by).
-- ---------------------------------------------------------------------------

-- End of schema.
