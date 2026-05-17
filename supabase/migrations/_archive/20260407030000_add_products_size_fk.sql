-- Add missing FK from products.size to size.size_id
-- (was a logical ref in AppSheet but never enforced in Supabase)
ALTER TABLE public.products
  ADD CONSTRAINT products_size_fkey
  FOREIGN KEY (size) REFERENCES public.size(size_id)
  ON DELETE SET NULL;
