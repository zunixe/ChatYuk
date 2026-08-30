-- Fix Google Sign-In 400: allow age=0 for new users (was 18+ only, new Google user inserts age 0)
alter table public.profiles drop constraint if exists profiles_age_18_check;
alter table public.profiles add constraint profiles_age_18_check check ((age is null) or (age = 0) or ((age >= 18) and (age <= 99)));
