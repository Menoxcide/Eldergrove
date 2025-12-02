-- handle new user
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
  begin
    insert into public.profiles (id)
    values (new.id);
    return new;
  end;
$$;

-- trigger the function on insert
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();