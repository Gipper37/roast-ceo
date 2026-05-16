-- Fix the build_product_name trigger to format channel names as Title Case
-- instead of using raw snake_case values (wholesale_shipped → Wholesale Shipped)

CREATE OR REPLACE FUNCTION build_product_name()
RETURNS TRIGGER AS $$
DECLARE
  v_group_name text;
  v_size_name  text;
  v_channel    text;
  v_parts      text[] := '{}';
BEGIN
  -- Look up group name
  SELECT group_name INTO v_group_name
    FROM product_groups WHERE group_id = NEW.group_id;

  -- Look up size name
  IF NEW.size IS NOT NULL THEN
    SELECT size_name INTO v_size_name
      FROM size WHERE size_id = NEW.size;
  END IF;

  -- Look up channel name and format as Title Case
  IF NEW.channel IS NOT NULL THEN
    SELECT initcap(replace(channel, '_', ' ')) INTO v_channel
      FROM channel WHERE channel_id = NEW.channel;
  END IF;

  -- Build name from non-null parts
  IF v_group_name IS NOT NULL THEN
    v_parts := v_parts || v_group_name;
  END IF;
  IF v_size_name IS NOT NULL AND v_size_name != '' THEN
    v_parts := v_parts || v_size_name;
  END IF;
  IF v_channel IS NOT NULL AND v_channel != '' THEN
    v_parts := v_parts || v_channel;
  END IF;

  NEW.product_name := array_to_string(v_parts, ' - ');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
