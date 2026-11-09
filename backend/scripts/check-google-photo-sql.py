#!/usr/bin/env python3
"""Offline actual-SQL regression. Own cluster, synthetic rows, no app DB/env URL.
Requires installed PostgreSQL and Node (type stripping); installs nothing.
Stops its server in finally; retains its small temporary directory for inspection.
"""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = [
    ('encoded_photo', 'https://maps.googleapis.com/maps/api/place/%70hoto', True),
    ('double_encoded', 'https://maps.googleapis.com/maps/api/place/%2570hoto', True),
    ('media', 'https://places.googleapis.com/v1/places/id/%70hotos/token/media', True),
    ('resource', 'places/id/%70hotos/token', True),
    ('usercontent', 'https://lh3.googleusercontent.com/%70/photo', True),
    ('segment_end', 'https://googleusercontent.com/p', True),
    ('gps', 'https://lh5.googleusercontent.com/gps-proxy/token', True),
    ('legacy_query', 'https://example.com/image?photo_reference=token', True),
    ('lookalike_suffix', 'https://googleusercontent.com.attacker.example/p/photo?sig=a%2Fb', False),
    ('lookalike_prefix', 'https://attackergoogleusercontent.com/p/photo', False),
    ('userinfo', 'https://googleusercontent.com@attacker.example/p/photo', False),
    ('google_userinfo', 'https://example.com@lh3.googleusercontent.com:443/p/photo', True),
    ('lookalike_maps', 'https://maps.googleapis.com.attacker.example/maps/api/place/photo', False),
    ('non_google_query', 'https://example.com/image?next=https://lh3.googleusercontent.com/p/photo', False),
    ('avatar', 'https://lh3.googleusercontent.com/a-/portrait?sig=a%2Fb', False),
    ('marketplace', 'https://cdn.example.com/marketplace/photo?id=%252F', False),
    ('own_bytes', ' HTTPS://cdn.example.com/a%2Fb.jpg?signature=%2B%25&x=1#Fragment ', False),
    ('malformed_percent', 'https://maps.googleapis.com/maps/api/place/%70hoto?bad=%ZZ', True),
    ('unicode_path', 'https://lh3.googleusercontent.com/p/%E5%8F%B0', True),
    ('fragment', 'https://example.com/a#https://lh3.googleusercontent.com/p/photo', False),
    ('dot_remove', 'https://lh3.googleusercontent.com/p/../a/avatar', False),
    ('dot_add', 'https://maps.googleapis.com/x/../maps/api/place/photo', True),
    ('unicode_whitespace', '%C2%A0https://lh3.googleusercontent.com/p/photo%C2%A0', True),
    ('whole_encoded', 'https%3A%2F%2Flh3.googleusercontent.com%2Fp%2Fphoto', True),
    ('zero_port', 'https://lh3.googleusercontent.com:00000443/p/photo', True),
    ('bad_port', 'https://lh3.googleusercontent.com:99999/p/photo', False),
    ('backslash', 'https://lh3.googleusercontent.com\\p\\photo', True),
]

def run(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode}): {result.stderr}')
    return result.stdout

def literal(value):
    return "'" + value.replace("'", "''") + "'"

# Differential oracle is the production TypeScript classifier, not a copied model.
node = shutil.which('node')
script = f"import {{isGooglePlacesPhotoURL}} from {json.dumps((ROOT / 'src/googlePlacesPhotoWrite.ts').as_uri())}; let s=''; for await (const c of process.stdin) s+=c; console.log(JSON.stringify(JSON.parse(s).map(v=>isGooglePlacesPhotoURL(v))));"
actual = json.loads(run([node, '--experimental-strip-types', '--input-type=module', '-e', script], input=json.dumps([url for _, url, _ in FIXTURES])))
assert actual == [expected for _, _, expected in FIXTURES], (actual, FIXTURES)

pg_bin = Path(run(['pg_config', '--bindir']).strip())
root = Path(tempfile.mkdtemp(prefix='save-photo-sql-'))
(root / 'socket').mkdir()
started = False
failures = []
try:
    run([str(pg_bin / 'initdb'), '-D', str(root / 'data'), '-U', 'photo_fixture', '-A', 'trust', '--no-locale', '--encoding=UTF8'])
    run([str(pg_bin / 'pg_ctl'), '-D', str(root / 'data'), '-l', str(root / 'server.log'), '-o', f"-k {root / 'socket'} -p 55443 -c listen_addresses=''", '-w', 'start'])
    started = True
    psql = [str(pg_bin / 'psql'), '-X', '-h', str(root / 'socket'), '-p', '55443', '-U', 'photo_fixture', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-Atq']
    def sql(statement):
        return run(psql, input=statement).strip()
    sql('create table public.places(id text primary key, business_photo_urls text[], source_image_url text);')
    verify = (ROOT / 'sql/google-photo-url-verify.sql').read_text()
    cleanup = (ROOT / 'sql/google-photo-url-cleanup.sql').read_text()
    for name, url, expected in FIXTURES:
        sql(f"truncate public.places; insert into public.places values ({literal(name)}, '{{}}', {literal(url)});")
        # The verifier must really run in a read-only transaction.
        result = sql('begin read only;\n' + verify + '\ncommit;')
        if result != f'0|{int(expected)}':
            failures.append(f'{name}: verifier {result!r}, expected 0|{int(expected)}')
    sql('truncate public.places;\n' + '\n'.join(f"insert into public.places values ({literal(name)}, '{{retired}}', {literal(url)});" for name, url, _ in FIXTURES))
    sql(cleanup)
    remaining = json.loads(sql("select coalesce(json_object_agg(id, source_image_url), '{}'::json) from public.places;"))
    for name, url, expected in FIXTURES:
        if remaining[name] != (None if expected else url):
            failures.append(f'{name}: cleanup changed wrong value {remaining[name]!r}')
    if sql(verify) != '0|0':
        failures.append('post-cleanup verifier is not 0|0')
    # More than eight layers is intentionally conservative versus the write cap.
    deep = 'https://maps.googleapis.com/maps/api/place/' + '%'+ '25' * 10 + '70hoto'
    sql(f"truncate public.places; insert into public.places values ('deep', '{{}}', {literal(deep)});")
    assert sql(verify) == '0|1', 'deep encoding must not produce a false zero'
    sql(cleanup)
    assert sql(verify) == '0|0'
    # PostgreSQL rejects invalid UTF-8/NUL. Never let that become a clean receipt,
    # and the transaction must roll back the retired-array update as well.
    for malformed in ['https://example.com/a%FF.jpg', 'https://example.com/a%00.jpg', 'https://ｌｈ３.googleusercontent.com/p/photo']:
        sql(f"truncate public.places; insert into public.places values ('malformed', '{{retired}}', {literal(malformed)});")
        for statement in [verify, cleanup]:
            result = subprocess.run(psql, input=statement, text=True, capture_output=True)
            assert result.returncode != 0, 'unclassifiable bytes must block rather than PASS'
        assert sql('select cardinality(business_photo_urls) from public.places') == '1'
        assert sql('select source_image_url from public.places') == malformed
    # Both scripts must embed exactly the same classifier CTE.
    marker = '-- BEGIN shared Google photo classifier'
    if marker in cleanup and marker in verify:
        end = '-- END shared Google photo classifier'
        assert cleanup.split(marker)[1].split(end)[0] == verify.split(marker)[1].split(end)[0]
    else:
        failures.append('missing paired classifier consistency markers')
finally:
    if started:
        run([str(pg_bin / 'pg_ctl'), '-D', str(root / 'data'), '-m', 'fast', '-w', 'stop'])
        status = subprocess.run([str(pg_bin / 'pg_ctl'), '-D', str(root / 'data'), 'status'], capture_output=True)
        assert status.returncode == 3, 'fixture server must be stopped'
    print(f'Fixture directory retained (server stopped): {root}')
if failures:
    raise AssertionError('\n'.join(failures))
print(f'PASS: {len(FIXTURES)} fixtures match production TypeScript and actual PostgreSQL; read-only verifier; exact non-Google bytes retained; cleanup then 0|0; identical classifiers; >8 layers caught; invalid UTF-8/NUL/IDNA host abort with rollback')
