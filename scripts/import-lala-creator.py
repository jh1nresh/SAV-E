#!/usr/bin/env python3
"""Offline, repeatable import of a frozen Lala public list. Never executes input JS.

Outputs a local Debug catalog, not personal saves or reviewed/live discovery.
Uncertain identities are retained as candidates without geographical pins.
"""
import argparse
from collections import defaultdict
from datetime import date
import hashlib
import json
import math
from pathlib import Path
import re
import unicodedata

REPOSITORY = 'https://github.com/2xin15/lala-food'
AUTHOR = 'zeke_6973'

def fold(value):
    return re.sub(r'\s+', '', unicodedata.normalize('NFKC', value).replace('臺', '台')).lower()

def name_key(value):
    return ''.join(c for c in fold(value).replace('馆', '館') if c.isalnum())

def address_key(value):
    value = fold(value)
    value = re.sub(r'([路街道])([一二三四五六七八九十])段', lambda m: m[1]+str('一二三四五六七八九十'.index(m[2])+1)+'段', value)
    value = re.sub(r'(\d+)號之(\d+)', r'\1-\2號', value)
    value = re.sub(r'(\d+)之(\d+)號', r'\1-\2號', value)
    value = re.sub(r'(b?\d+)f', r'\1樓', value)
    value = value.replace('一樓', '1樓')
    # Keep city, district and the entire unit/floor. Remove only postal prefix and village.
    value = re.sub(r'^(?:\d{3,6})?(?:台灣)?', '', value)
    return re.sub(r'(?<=[區鄉鎮])[^區鄉鎮市路街巷弄號\d]{1,8}里', '', value)

def distance(a, b):
    return math.hypot((a['longitude']-b['longitude'])*111320*math.cos(math.radians(a['latitude'])),
                      (a['latitude']-b['latitude'])*110540)

def string(value, limit, empty=False):
    if not isinstance(value, str) or (not empty and not value.strip()) or len(value)>limit or re.search(r'[\x00-\x08\x0b-\x1f\x7f]',value):
        raise ValueError('Invalid text')
    return value

def assignment(path, name):
    raw=Path(path).read_text()
    # Only comments plus a single JSON literal assignment. No eval, VM or module import.
    match=re.fullmatch(r'\s*(?://[^\n]*\n\s*)*window\.'+re.escape(name)+r'\s*=\s*(\{.*\})\s*;?\s*',raw,re.S)
    if not match: raise ValueError('Expected JSON-only '+name)
    return json.loads(match[1], parse_constant=lambda s: (_ for _ in ()).throw(ValueError(s)))

def identity(place):
    return (place['provider'], place['providerPlaceID'])

def native_matches(review, row):
    """Explicit reviewed provider observations; never broaden the general radius."""
    matches = review.get('nativeMatches', [])
    if not isinstance(matches, list) or len(matches) > 8:
        raise ValueError('Invalid native matches')
    result = []
    for match in matches:
        if not isinstance(match, dict) or match.get('provider') != 'apple_maps':
            raise ValueError('Invalid native provider')
        pid = string(match.get('providerPlaceId'), 200)
        if not re.fullmatch(r'[A-Za-z0-9_-]+', pid):
            raise ValueError('Invalid native identity')
        string(match.get('evidence'), 2000)
        date.fromisoformat(string(match.get('observedAt'), 10))
        name = string(match.get('name'), 300)
        address = string(match.get('address'), 500)
        for key, limit in [('latitude', 90), ('longitude', 180)]:
            value = match.get(key)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or abs(value) > limit:
                raise ValueError('Invalid native coordinates')
        # This is a reviewed local discrepancy, not permission to attach distant venues.
        if distance(row, match) > 1000:
            raise ValueError('Native observation is outside the reviewed locality')
        result.append(dict(name=name, address=address, latitude=match['latitude'],
                           longitude=match['longitude'], provider='apple_maps', providerPlaceId=pid))
    return result

def read_inputs(data, posts, duplicate_variants=None):
    duplicate_variants = duplicate_variants or {}
    unique={}
    for state in ('visited','wish'):
        rows=data[state]
        if not isinstance(rows,list): raise ValueError('Invalid list')
        for source in rows:
            cid=source.get('cid')
            if not isinstance(cid,str) or not re.fullmatch(r'[1-9]\d{0,19}',cid): raise ValueError('Invalid CID')
            row={'cid':cid, 'name':string(source['name'],300), 'address':string(source['addr'],500),
                 'latitude':source['lat'], 'longitude':source['lng'], 'city':string(source['city'],100),
                 'category':string(source['cat'],100), 'lists':[state]}
            if any(isinstance(row[k],bool) or not isinstance(row[k],(int,float)) or not math.isfinite(row[k]) for k in ('latitude','longitude')) or not -90<=row['latitude']<=90 or not -180<=row['longitude']<=180 or (row['latitude']==row['longitude']==0):
                raise ValueError('Invalid coordinates')
            if cid in unique:
                previous=unique[cid]
                if name_key(previous['name'])!=name_key(row['name']) or distance(previous,row)>1:
                    raise ValueError('Conflicting CID '+cid)
                if address_key(previous['address'])!=address_key(row['address']):
                    approved = duplicate_variants.get(cid)
                    if approved != [previous['address'], row['address']]:
                        raise ValueError('Conflicting CID address '+cid)
                previous.setdefault('sourceVariants', []).append({k:row[k] for k in ('name','address')})
                previous['lists']=sorted(set(previous['lists']+[state]))
            else: unique[cid]=row
    orphan=set(posts)-set(unique)
    if orphan: raise ValueError('Posts without a list place: '+str(sorted(orphan)))
    for cid,row in unique.items():
        originals={}
        for p in posts.get(cid,[]):
            url=string(p['url'],2048)
            if not re.fullmatch(r'https://www\.threads\.(?:com|net)/@'+AUTHOR+r'/post/[A-Za-z0-9_-]+/?',url): raise ValueError('Unexpected original URL')
            url=url.replace('threads.net','threads.com').rstrip('/')
            day=str(date.fromisoformat(p['date']))
            item={'url':url,'text':string(p['text'],4000,True),'date':day,'author':AUTHOR}
            if url in originals and originals[url]!=item: raise ValueError('Conflicting post')
            originals[url]=item
        row['posts']=list(originals.values())
    return [unique[k] for k in sorted(unique)]

def build(data, posts, city, existing, projection, revision, captured_at, overrides=None):
    if not re.fullmatch(r'[a-f0-9]{40}',revision): raise ValueError('Expected immutable source commit')
    date.fromisoformat(captured_at)
    review=overrides or {}
    rows=read_inputs(data,posts,review.get("duplicateAddressVariants"))
    features=city['features']
    city_by_id={f['properties']['placeId']:f for f in features}
    if len(city_by_id)!=len(features): raise ValueError('Duplicate base place ID')
    target=[]
    for f in features:
        p=f['properties']; point=f['geometry']['coordinates']
        address=p.get('detail','')
        if p.get('district') and not re.search('[縣市]',address[:8]):
            address='台北市'+('' if address.startswith(p['district']) else p['district'])+address
        target.append({'id':p['placeId'],'name':p.get('name',''),'address':address,
                       'latitude':point[1],'longitude':point[0], 'aliases':[]})
    projected={identity(p):p['placeId'] for p in projection.get('venues',[])+projection.get('verifiedPins',[])}
    for p in existing:
        pid=projected.get(identity(p),'savvy/'+p['provider']+'/'+p['providerPlaceID'])
        target.append({'id':pid,'name':p['name'],'address':p['address'],'latitude':p['latitude'],
                       'longitude':p['longitude'],'aliases':[{'provider':p['provider'],'id':p['providerPlaceID']}]})
    by_address=defaultdict(list)
    for t in target:
        by_address[address_key(t['address'])].append(t)
    overrides=review.get("places", {})
    if set(overrides)-{r['cid'] for r in rows}: raise ValueError('Unknown override CID')
    entries=[];pending=[]
    for row in rows:
        street_matches=by_address[address_key(row['address'])]
        exact=[t for t in street_matches if distance(row,t)<=65 and
               (name_key(t['name'])==name_key(row['name']) or
                (min(len(name_key(t['name'])),len(name_key(row['name'])))>=3 and
                 (name_key(t['name']) in name_key(row['name']) or name_key(row['name']) in name_key(t['name']))))]
        method='name_address_coordinates'
        nearby=[t for t in target if distance(row,t)<=120 and name_key(t['name']) and
                (name_key(row['name']) in name_key(t['name']) or name_key(t['name']) in name_key(row['name']))]
        nearby += [t for t in street_matches if distance(row,t)<=65 and t not in nearby]
        distinct=False
        if row['cid'] in overrides:
            o=overrides[row['cid']]
            if o['sourceName']!=row['name'] or o['sourceAddress']!=row['address'] or not o.get('evidence'): raise ValueError('Stale review')
            decision=o.get('decision','same_branch')
            if decision=='distinct_place':
                rejected=o.get('rejectedCandidates',[])
                expected={(t['id'],t['name'],t['address']) for t in nearby+exact}
                actual={(t['placeId'],t['targetName'],t['targetAddress']) for t in rejected}
                if not actual or expected!=actual: raise ValueError('Stale distinct-place review')
                exact=[];distinct=True;method='reviewed_distinct_place'
            else:
                if decision not in ('same_branch','same_named_area'): raise ValueError('Unknown review decision')
                limit=250 if decision=='same_named_area' else 85
                exact=[t for t in target if t['id']==o['placeId'] and t['name']==o['targetName'] and t['address']==o['targetAddress'] and distance(row,t)<=limit]
                if not exact: raise ValueError('Invalid reviewed mapping')
                if decision=='same_named_area' and (not o['placeId'].startswith(('poi/way/','park/')) or name_key(o['targetName'])!=name_key(row['name'])):
                    raise ValueError('Area review cannot widen branch matching')
                method='reviewed_branch'
        ids=set(t['id'] for t in exact)
        # Existing native and map identities may coexist; only a previously reviewed projection unifies them.
        if len(ids)>1:
            pending.append({**row,'reason':'multiple_existing_matches','candidates':sorted(ids)});continue
        if not ids and not distinct:
            # A nearby same-name/contained-name venue may be the same branch with incomplete metadata.
            if nearby:
                pending.append({**row,'reason':'possible_existing_branch','candidates':sorted(set(t['id'] for t in nearby))});continue
        pid=next(iter(ids)) if ids else 'creator/lala/'+row['cid']
        aliases={ (a['provider'],a['id']) for t in exact for a in t['aliases'] }
        matched_places=[{k:t[k] for k in ('name','address','latitude','longitude')} for t in exact if t['name']]
        if row['cid'] in overrides:
            matched_places.extend(native_matches(overrides[row['cid']], row))
        entries.append({**row,'placeId':pid,'mapPlaceIds':[pid], 'isNew':not bool(ids),
                        'matchMethod':method if ids or distinct else 'source_cid',
                        'matchedPlaces':matched_places,
                        'aliases':[{'provider':p,'id':i} for p,i in sorted(aliases)]})
    # Two upstream CIDs claiming the same existing pin are review candidates, not silent overwrites.
    claims=defaultdict(list)
    native_claims = {}
    for row in entries:
        for match in row['matchedPlaces']:
            if 'providerPlaceId' not in match: continue
            key = (match['provider'], match['providerPlaceId'])
            if key in native_claims and native_claims[key] != row['cid']:
                raise ValueError('Native identity claimed by multiple branches')
            native_claims[key] = row['cid']
    for row in entries: claims[row['placeId']].append(row)
    kept=[]
    for pid,items in claims.items():
        if len(items)>1:
            pending.extend({**r,'reason':'multiple_source_cids','candidates':[pid]} for r in items)
        else: kept.extend(items)
    summary={'visited':len(data['visited']),'wish':len(data['wish']),'uniquePlaces':len(rows),
             'overlap':sum(len(r['lists'])==2 for r in rows),
             'attachedExisting':sum(not r['isNew'] for r in kept),'newPlaces':sum(r['isNew'] for r in kept),
             'pendingPlaces':len(pending),'postPlaces':sum(bool(r['posts']) for r in rows),
             'postAssociations':sum(len(r['posts']) for r in rows),
             'attachedPostAssociations':sum(len(r['posts']) for r in kept),
             'pendingPostAssociations':sum(len(r['posts']) for r in pending)}
    return {'schemaVersion':1,'scope':'local_creator_preview','creator':AUTHOR,'creatorName':'拉拉熊',
            'sourceRepository':REPOSITORY,'sourceRevision':revision,'capturedAt':captured_at,'updated':data['updated'],
            'sourceLists':{k:'https://www.google.com/maps/@/data=!4m2!2m1!1s'+string(data['lists'][k],200) for k in ('visited','wish')},
            'summary':summary,'entries':sorted(kept,key=lambda r:r['cid']), 'pending':sorted(pending,key=lambda r:r['cid'])}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for key in ('data','posts','city','existing','projection','revision','captured-at','output'):p.add_argument('--'+key,required=True)
    p.add_argument('--reviewed')
    a=p.parse_args();read=lambda f:json.loads(Path(f).read_text())
    result=build(assignment(a.data,'LALA_DATA'),assignment(a.posts,'LALA_POSTS'),read(a.city),read(a.existing),
                 read(a.projection),a.revision,a.captured_at,read(a.reviewed) if a.reviewed else None)
    result['inputSHA256']={k:hashlib.sha256(Path(getattr(a,k)).read_bytes()).hexdigest() for k in ('data','posts','city','existing','projection')}
    if a.reviewed: result['inputSHA256']['reviewed']=hashlib.sha256(Path(a.reviewed).read_bytes()).hexdigest()
    Path(a.output).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result['summary'],ensure_ascii=False))
if __name__=='__main__':main()
