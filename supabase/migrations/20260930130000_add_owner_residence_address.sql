-- =========================================================
-- MIRADOR GOLF 1
-- ADRESSE COMPLETE DE RESIDENCE DU PROPRIETAIRE
--
-- Complète 20260930120000_add_owner_residence_location.sql en
-- ajoutant l'adresse postale du propriétaire (rue + code postal)
-- au formulaire public de collecte (collecte.html). La validation
-- obligatoire de l'adresse est assurée côté formulaire ; les
-- colonnes restent nullable en base pour ne pas casser les
-- lignes déjà présentes dans owner_submissions. Le code postal
-- est facultatif, y compris côté formulaire.
-- =========================================================


-- ---------------------------------------------------------
-- 1. Nouvelles colonnes
-- ---------------------------------------------------------

alter table public.owner_submissions
add column if not exists residence_address text,
add column if not exists residence_postal_code text;


-- Le formulaire public (rôle anon) doit pouvoir écrire ces
-- colonnes ; les colonnes déjà autorisées (grants précédents)
-- restent inchangées, celle-ci s'ajoute aux privilèges existants.

grant insert (
    residence_address,
    residence_postal_code
)
on public.owner_submissions
to anon;
