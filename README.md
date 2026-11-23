# PERBAKIN Express.js Backend

REST API starter for the PostgreSQL schema in `postgresql_schema.sql`. The project connects to your local PostgreSQL database named **`perbakin_stg`**.

## 1. Requirements

- Node.js 20+
- PostgreSQL 13+
- pgAdmin 4 (or `psql`)

## 2. Create the database and import the schema

In pgAdmin:
1. Connect to your local PostgreSQL server.
2. Right-click **Databases → Create → Database**.
3. Set the database name to `perbakin_stg`.
4. Open **Query Tool** while `perbakin_stg` is selected.
5. Open and execute the supplied `postgresql_schema.sql`.

The SQL creates the `auth` and `public` schemas, `auth.users`, the `public` tables, and the `public.app_role` enum. It does not create the database itself.

> Important: this project targets the standalone PostgreSQL version of `auth.users` in the supplied SQL. Do not run this auth implementation unchanged against Supabase-managed Auth. The SQL comments also note that the original trigger and two custom JSON validation functions were not supplied, so their behavior is not implemented here.

## 3. Configure and run

```bash
# From this project directory
npm install
```

Copy `.env.example` to `.env`, then set your local PostgreSQL credentials:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=perbakin_stg
DB_USER=postgres
DB_PASSWORD=your_actual_postgres_password
JWT_SECRET=use_a_random_secret_of_32_chars_or_more
```

Generate a strong JWT secret if needed:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```

Then start the API:

```bash
npm run dev
```

The API defaults to `http://localhost:3000`.

Check the database connection:

```http
GET http://localhost:3000/health
```

## 4. Authentication

### Register

`POST /api/auth/register`

```json
{
  "name": "John Doe",
  "email": "john@example.com",
  "password": "password123"
}
```

Registration creates:
- a row in `auth.users`
- a BCrypt password hash in `auth.users.encrypted_password`
- a `user_roles` row with role `user`

The endpoint returns a JWT. The API currently marks newly registered emails as confirmed (`email_confirmed_at = now()`) because this local starter does not implement an email confirmation workflow. Add a real verification flow before production use.

### Login

`POST /api/auth/login`

```json
{
  "email": "john@example.com",
  "password": "password123"
}
```

### Current user

`GET /api/auth/me`

Header:

```http
Authorization: Bearer YOUR_JWT
```

### Admin access

All resource reads require authentication. Resource create/update/delete operations require role `admin`.

To promote a local account to admin in pgAdmin (replace the email):

```sql
INSERT INTO public.user_roles (user_id, role)
SELECT id, 'admin'::public.app_role
FROM auth.users
WHERE lower(email) = lower('admin@example.com');
```

The supplied schema does not define a unique constraint on `user_roles.user_id`, so avoid running this repeatedly for the same account. The API prioritizes the `admin` role if multiple role rows exist.

Do not expose admin promotion as a public API endpoint.

## 5. CRUD API

The generic resource router uses an explicit allowlist of the public tables from the supplied schema. Table names and column names are validated, and values are passed as SQL parameters.

| Method | Endpoint | Access | Purpose |
|---|---|---|---|
| GET | `/api/:table` | Authenticated | List rows |
| GET | `/api/:table/:id` | Authenticated | Get one row |
| POST | `/api/:table` | Admin | Insert row |
| PATCH | `/api/:table/:id` | Admin | Update row |
| DELETE | `/api/:table/:id` | Admin | Delete row |
| GET | `/api/my-member` | Authenticated | Get the current user's member record |

Example list request:

```http
GET /api/members?limit=20&offset=0&orderBy=date_created&direction=desc
Authorization: Bearer YOUR_JWT
```

Example create member (admin token):

```http
POST /api/members
Authorization: Bearer ADMIN_JWT
Content-Type: application/json

{
  "name": "John Doe",
  "telepon": "081234567890",
  "user_id": "UUID-OF-AUTH-USER",
  "membership_status": true
}
```

Example update:

```http
PATCH /api/members/MEMBER_UUID
Authorization: Bearer ADMIN_JWT
Content-Type: application/json

{
  "address": "Bogor",
  "membership_status": true
}
```

Use the exact column names from PostgreSQL. Examples include `nama_club`, `no_kta`, `no_ktp`, `tanggal_dari`, `tanggal_sampai`, `member_id`, and `created_at`.

### Available `:table` values

`members`, `payment`, `senjata`, `document_review`, `user_roles`, `event`, `izin`, `content`, `member_review`, `memberform`, `member_sponsor`, `sponsor_form`, `izin_submission_review`, `media_file`, `ipaymu_test_payments`, `registration_qris_payments`, `member_statistics`, `event_history`, `klub`, `site_content`.

`auth.users` is intentionally not exposed through generic CRUD. Use the authentication endpoints for login and registration.

Some tables use a non-`id` primary key (`ipaymu_test_payments.reference_id` and `registration_qris_payments.order_id`). The single-record routes support those keys as the URL identifier.

## 6. Postman quick test

1. Register with `POST http://localhost:3000/api/auth/register`.
2. Copy `data.token` from the response.
3. In Postman, create a collection variable `token` and set it to that token.
4. Use `Authorization → Bearer Token → {{token}}`.
5. Test `GET /api/auth/me` and `GET /api/my-member`.
6. Promote an account to admin using the SQL above, log in again, then test resource POST/PATCH/DELETE.

## 7. Project layout

```text
perbakin-express-backend/
├── src/
│   ├── config/
│   │   ├── db.js
│   │   └── env.js
│   ├── middleware/
│   │   └── auth.js
│   ├── routes/
│   │   ├── auth.routes.js
│   │   ├── member.routes.js
│   │   └── resource.routes.js
│   ├── utils/
│   │   ├── asyncHandler.js
│   │   └── httpError.js
│   └── server.js
├── .env.example
├── .gitignore
└── package.json
```

## 8. Notes and production checklist

- Passwords are hashed with BCrypt. Never store plaintext passwords.
- JWT secret and database credentials belong in `.env`, never commit `.env`.
- Use HTTPS and a restricted `CORS_ORIGIN` in production.
- The starter auto-confirms local registrations. Implement email verification and password reset before production.
- Resource reads are broadly available to authenticated accounts in this starter. If your app needs member-level row privacy, add per-table ownership checks before exposing member, identity, firearm-registration, permit, or payment data to ordinary users.
- `document_review.owner_id`, `event_history` foreign keys, `member_statistics.member_id`, `izin_submission_review` references, and `site_content.updated_by` have no FK constraints in the supplied SQL. The backend does not invent those relationships.
- The SQL source omitted `handle_new_user_role()`, `valid_izin_group()`, and `valid_izin_declarations()`. Those trigger/validation behaviors are not recreated.
- Payment tables here are database CRUD only. This project does not integrate or verify a payment gateway.
- Add audit logging, pagination totals, request validation per resource, automated tests, and backups before production deployment.
