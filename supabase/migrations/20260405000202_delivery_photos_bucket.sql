-- Create storage bucket for delivery photos
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'delivery-photos',
  'delivery-photos',
  true,
  10485760, -- 10 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload
CREATE POLICY "Authenticated users can upload delivery photos"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'delivery-photos');

-- Allow public read
CREATE POLICY "Public read delivery photos"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'delivery-photos');

-- Allow authenticated users to update their uploads
CREATE POLICY "Authenticated users can update delivery photos"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'delivery-photos');
