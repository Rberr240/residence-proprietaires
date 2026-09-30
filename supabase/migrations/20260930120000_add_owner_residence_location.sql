-- =========================================================
-- MIRADOR GOLF 1
-- LIEU DE RESIDENCE DU PROPRIETAIRE
--
-- Ajoute au formulaire public de collecte (collecte.html) trois
-- colonnes optionnelles décrivant le lieu de résidence du
-- propriétaire (Maroc / étranger, ville, pays). La validation
-- obligatoire est assurée côté formulaire ; les colonnes restent
-- nullable en base pour ne pas casser les lignes déjà présentes
-- dans owner_submissions.
--
-- Corrige également la contrainte building_code : le formulaire
-- proposait "Bloc L" mais envoyait par erreur la valeur "K"
-- (bug corrigé côté frontend dans le même changement). La valeur
-- 'L' n'était pas acceptée par la contrainte existante ; sans ce
-- correctif, toute soumission "Bloc L" échouerait désormais avec
-- la valeur corrigée.
-- =========================================================


-- ---------------------------------------------------------
-- 1. Nouvelles colonnes
-- ---------------------------------------------------------

alter table public.owner_submissions
add column if not exists residence_type text,
add column if not exists residence_city text,
add column if not exists residence_country text;


alter table public.owner_submissions
drop constraint if exists owner_submissions_residence_type_check;

alter table public.owner_submissions
add constraint owner_submissions_residence_type_check
check (
    residence_type is null
    or residence_type in ('morocco', 'abroad')
);


-- Le formulaire public (rôle anon) doit pouvoir écrire ces
-- colonnes ; les colonnes déjà autorisées (grant insert initial
-- de 20260810190254_add_owner_public_intake.sql) restent
-- inchangées, celle-ci s'ajoute aux privilèges existants.

grant insert (
    residence_type,
    residence_city,
    residence_country
)
on public.owner_submissions
to anon;


-- ---------------------------------------------------------
-- 2. Correctif building_code : ajout de 'L' (Bloc L)
-- ---------------------------------------------------------

alter table public.owner_submissions
drop constraint if exists owner_submissions_building_code_check;

alter table public.owner_submissions
add constraint owner_submissions_building_code_check
check (
    building_code in (
        'A','B','C','D','E','F',
        'H','I','J','K','L','HOTEL'
    )
);
