-- Correct historical streak awards that kept the default bronze tier when the
-- tiered award migration met an existing dedupe key.

update public.achievements
set tier = case (metadata->>'days')::integer
  when 1 then 'bronze'
  when 3 then 'silver'
  when 7 then 'gold'
end
where achievement_type = 'together_streak'
  and (metadata->>'days')::integer in (1, 3, 7)
  and tier is distinct from case (metadata->>'days')::integer
    when 1 then 'bronze'
    when 3 then 'silver'
    when 7 then 'gold'
  end;
