-- Runner Tips: repairs accented letters in tips that were pasted with the wrong encoding.
-- ASCII only on purpose, so this file can't get mangled the same way.
update tips set
  title    = convert_from(convert_to(title, 'LATIN1'), 'UTF8'),
  body     = convert_from(convert_to(body, 'LATIN1'), 'UTF8'),
  title_en = convert_from(convert_to(title_en, 'LATIN1'), 'UTF8'),
  body_en  = convert_from(convert_to(body_en, 'LATIN1'), 'UTF8')
where position(U&'\00C3' in title || body || coalesce(title_en, '') || coalesce(body_en, '')) > 0;
