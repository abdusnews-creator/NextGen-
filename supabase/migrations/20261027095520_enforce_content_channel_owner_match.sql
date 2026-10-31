ALTER TABLE public.channels
  ADD CONSTRAINT channels_id_owner_id_unique UNIQUE (id, owner_id);

ALTER TABLE public.content_items
  DROP CONSTRAINT IF EXISTS content_items_channel_id_fkey;

ALTER TABLE public.content_items
  DROP CONSTRAINT IF EXISTS content_channel_owner_match;

ALTER TABLE public.content_items
  ADD CONSTRAINT content_channel_owner_match
  FOREIGN KEY (channel_id, owner_id)
  REFERENCES public.channels (id, owner_id);
