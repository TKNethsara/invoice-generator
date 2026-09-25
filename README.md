# InvoicePro

A vanilla HTML/CSS/JavaScript invoice manager powered by Supabase Auth, PostgreSQL, RLS and Storage.

## 1. Supabase setup

1. Create a Supabase project.
2. Open **SQL Editor** and run `supabase/schema.sql`.
3. In **Authentication → URL Configuration**, add your deployed site URL and the local URL you use for testing.
4. The SQL creates the `business-logos` private bucket and its storage policies.
5. Create a normal account through `register.html`.
6. After the account exists, open Supabase SQL Editor and promote that account to admin using:
   ```sql
   insert into public.user_roles (user_id, role)
   select id, 'admin'::public.app_role
   from auth.users
   where email = 'YOUR_ADMIN_EMAIL@example.com'
   on conflict (user_id) do update set role = excluded.role;
   ```
7. Sign out/in again so the new role is present in the session.
8. For the optional admin "Delete User" action, deploy `supabase/functions/admin-delete-user` as a Supabase Edge Function and set the function's secrets. The browser must never receive the service-role key.

## 2. Frontend configuration

`js/config.js` is generated at deploy time. For GitHub Pages, add these GitHub repository secrets:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY` (publishable/anon key only)

The included GitHub Actions workflow generates `js/config.js` during deployment. A browser-visible publishable/anon key is not a secret and must be protected by RLS; the Supabase `service_role` key must never be exposed to the browser.

For local testing, copy `js/config.example.js` to `js/config.js` and fill in the URL and publishable/anon key.

## 3. Run

Because ES modules are used, serve the folder through a web server. For example:

```bash
python -m http.server 5500
```

Then open `http://localhost:5500/login.html`.

## 4. Edge Function for deleting Auth users

Deploy the included function:

```bash
supabase functions deploy admin-delete-user
```

Set `SUPABASE_SERVICE_ROLE_KEY` as an Edge Function secret. The function checks that the caller is an admin before using the service role to delete the target Auth user.

## 5. Notes

- RLS is the primary authorization boundary.
- Normal users can only read/write rows owned by their own `user_id`.
- `invoice_items` are protected through their parent invoice.
- Roles cannot be changed by normal users.
- Admin views are additionally protected by server-side RLS.
- The app uses jsPDF from a CDN for client-side PDF generation. For highly exact print layouts, browser print/PDF is also available.
