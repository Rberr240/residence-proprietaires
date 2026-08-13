-- =========================================================
-- MIRADOR GOLF 1
-- Correction des statuts meetings pour V2
-- =========================================================
--
-- On conserve également les anciens statuts afin de ne
-- casser aucune donnée historique.
-- =========================================================

alter table public.meetings
drop constraint if exists meetings_status_check;


alter table public.meetings
add constraint meetings_status_check
check (
    status in (
        'draft',
        'scheduled',
        'published',
        'closed',
        'completed',
        'cancelled'
    )
);