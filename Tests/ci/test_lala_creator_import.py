import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('lala', ROOT/'scripts/import-lala-creator.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class LalaImportTests(unittest.TestCase):
    def row(self, cid='123', name='同名餐廳 大安店', addr='臺北市大安區仁愛路四段10號2樓', lat=25.04):
        return dict(cid=cid, name=name, addr=addr, city='台北市', cat='餐廳', lat=lat, lng=121.54)

    def data(self, visited=None, wish=None):
        return dict(updated='2026-11-27', lists={'visited':'visited123','wish':'wish123'},
                    visited=visited or [], wish=wish or [])

    def feature(self, pid='poi/node/1', name='同名餐廳 大安店', address='仁愛路四段10號2樓'):
        return dict(type='Feature', id=pid, geometry=dict(type='Point',coordinates=[121.54,25.04]),
                    properties=dict(placeId=pid,name=name,detail=address,district='大安區'))

    def run_import(self, data, features=None, posts=None, existing=None, review=None):
        return mod.build(data, posts or {}, {'features':features or []}, existing or [], {}, 'a'*40, '2026-11-27',review)

    def test_lists_merge_by_cid_but_keep_both_creator_states(self):
        r=self.row();out=self.run_import(self.data([r],[r]))
        self.assertEqual(len(out['entries']),1)
        self.assertEqual(out['entries'][0]['lists'],['visited','wish'])
        self.assertEqual(out['summary']['overlap'],1)
        self.assertNotIn('visitedAt',out['entries'][0])

    def test_existing_branch_keeps_id_and_other_floor_is_not_borrowed(self):
        out=self.run_import(self.data([self.row()]),[self.feature(),self.feature('poi/node/2',address='仁愛路四段10號3樓')])
        self.assertEqual(out['entries'][0]['placeId'],'poi/node/1')
        self.assertFalse(out['entries'][0]['isNew'])

    def test_wrong_floor_or_incomplete_address_remains_pending(self):
        for addr in ['仁愛路四段10號3樓','仁愛路四段10號','大安區']:
            out=self.run_import(self.data([self.row()]),[self.feature(address=addr)])
            self.assertEqual(out['entries'],[])
            self.assertEqual(len(out['pending']),1)

    def test_same_brand_different_street_does_not_merge(self):
        out=self.run_import(self.data([self.row()]),[self.feature(address='仁愛路四段11號2樓')])
        self.assertEqual(out['entries'],[])

    def test_multiple_existing_identities_remain_pending(self):
        out=self.run_import(self.data([self.row()]),[self.feature(),self.feature('poi/node/2')])
        self.assertEqual(out['pending'][0]['reason'],'multiple_existing_matches')

    def test_same_cid_with_conflicting_location_is_rejected(self):
        with self.assertRaises(ValueError):self.run_import(self.data([self.row()],[self.row(lat=25.10)]))

    def test_address_variants_need_exact_review(self):
        a=self.row();b={**a,'addr':'No.10 Some other road'}
        with self.assertRaises(ValueError):self.run_import(self.data([a],[b]))
        review={'duplicateAddressVariants':{'123':[a['addr'],b['addr']]}}
        out=self.run_import(self.data([a],[b]),review=review)
        self.assertEqual(len(out['entries']),1)

    def test_js_input_is_not_executed(self):
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/'input.js'
            for value in ['window.LALA_DATA = {}; alert(1)', 'window.LALA_DATA = {"a":undefined}', 'window.LALA_DATA = {"a":NaN}']:
                path.write_text(value)
                with self.assertRaises((ValueError,json.JSONDecodeError)):mod.assignment(path,'LALA_DATA')

    def test_invalid_coordinates_urls_or_orphan_posts_fail(self):
        for lat in [True, float('inf'), 91]:
            with self.assertRaises(ValueError):self.run_import(self.data([self.row(lat=lat)]))
        post={'url':'https://www.threads.com/@zeke_6973/post/abc','date':'2026-11-01','text':'原文'}
        for url in ['javascript:alert(1)',post['url']+'?token=secret',post['url'].replace('zeke_6973','another')]:
            with self.assertRaises(ValueError):self.run_import(self.data([self.row()]),posts={'123':[{**post,'url':url}]})
        with self.assertRaises(ValueError):self.run_import(self.data(),posts={'123':[post]})

    def test_post_text_is_separate_from_notes_and_not_fabricated(self):
        row=self.row();post={'url':'https://www.threads.com/@zeke_6973/post/abc','date':'2026-11-01','text':'原文 <script>not HTML</script>'}
        out=self.run_import(self.data([row]),posts={'123':[post,post]})
        self.assertEqual(out['entries'][0]['posts'][0]['text'],post['text'])
        self.assertEqual(len(out['entries'][0]['posts']),1)
        self.assertNotIn('note',out['entries'][0])
        self.assertEqual(self.run_import(self.data([row]))['entries'][0]['posts'],[])

    def test_repeatable_and_inputs_not_mutated(self):
        data=self.data([self.row()]);before=copy.deepcopy(data)
        a=self.run_import(data);b=self.run_import(data)
        self.assertEqual(a,b);self.assertEqual(data,before)

    def test_stale_review_is_rejected(self):
        review={'places':{'123':{'sourceName':'changed','sourceAddress':'x','evidence':'test'}}}
        with self.assertRaises(ValueError):self.run_import(self.data([self.row()]),review=review)

    def native_review(self):
        row=self.row()
        return {'places':{'123':{'sourceName':row['name'],'sourceAddress':row['addr'],
            'placeId':'poi/node/1','targetName':row['name'],'targetAddress':row['addr'].replace('臺','台'),
            'evidence':'Exact canonical branch', 'nativeMatches':[{
                'provider':'apple_maps','providerPlaceId':'H123','name':'Observed branch',
                'address':'Observed complete branch address','latitude':25.036,'longitude':121.54,
                'observedAt':'2026-11-27','evidence':'Live native search observation, exact branch address'}]}}}

    def test_reviewed_native_coordinates_do_not_move_or_duplicate_map_pin(self):
        review=self.native_review()
        out=self.run_import(self.data([self.row()]),[self.feature()],review=review)
        entry=out['entries'][0]
        self.assertEqual(len(out['entries']),1)
        self.assertEqual(entry['placeId'],'poi/node/1')
        self.assertEqual(entry['latitude'],25.04)
        self.assertEqual(entry['aliases'],[])
        self.assertEqual(entry['matchedPlaces'][-1]['providerPlaceId'],'H123')
        self.assertEqual(entry['matchedPlaces'][-1]['latitude'],25.036)

    def test_native_review_requires_bounded_identity_coordinates_and_evidence(self):
        for key,value in [('provider','google'),('providerPlaceId',''),('providerPlaceId','../bad'),
                          ('address',''),('latitude',True),('latitude',float('nan')),
                          ('latitude',25.5),('evidence',''),('observedAt','today')]:
            review=self.native_review();review['places']['123']['nativeMatches'][0][key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                self.run_import(self.data([self.row()]),[self.feature()],review=review)

    def test_provider_identity_cannot_be_claimed_by_two_branches(self):
        review=self.native_review(); second=self.row(cid='456',addr='臺北市大安區仁愛路四段11號2樓')
        review['places']['456']=copy.deepcopy(review['places']['123'])
        review['places']['456'].update(sourceAddress=second['addr'],targetAddress=second['addr'].replace('臺','台'),placeId='poi/node/2')
        with self.assertRaisesRegex(ValueError,'multiple branches'):
            self.run_import(self.data([self.row(),second]),[self.feature(),self.feature('poi/node/2',address='仁愛路四段11號2樓')],review=review)

    def test_distinct_tenant_requires_frozen_rejection_of_every_candidate(self):
        row=self.row(); f=self.feature(name='某百貨'); t=f['properties']
        review={'places':{'123':{'sourceName':row['name'],'sourceAddress':row['addr'],
            'decision':'distinct_place','evidence':'Restaurant tenant is not the department store',
            'rejectedCandidates':[{'placeId':t['placeId'],'targetName':t['name'],
                                   'targetAddress':'台北市大安區'+t['detail']}]}}}
        result=self.run_import(self.data([row]),[f],review=review)
        self.assertEqual(result['entries'][0]['placeId'],'creator/lala/123')
        self.assertEqual(result['pending'],[])
        with self.assertRaises(ValueError):
            self.run_import(self.data([row]),[f,self.feature('poi/node/2',name='另一店')],review=review)
        f['properties']['name']='Changed tenant'
        with self.assertRaises(ValueError):self.run_import(self.data([row]),[f],review=review)

    def test_area_exception_does_not_widen_restaurant_branch_matching(self):
        row=self.row(); f=self.feature(); f['geometry']['coordinates'][0]+=0.0015
        review={'places':{'123':{'sourceName':row['name'],'sourceAddress':row['addr'],
            'decision':'same_named_area','evidence':'Not an area', 'placeId':'poi/node/1',
            'targetName':row['name'],'targetAddress':'台北市大安區'+f['properties']['detail']}}}
        with self.assertRaises(ValueError):self.run_import(self.data([row]),[f],review=review)

    def test_real_review_preserves_shop_not_container_or_neighbour(self):
        d=json.loads((ROOT/'Prototypes/CreatorLists/lala/CreatorPlaceSources.json').read_text())
        rows={r['cid']:r for r in d['entries']}
        self.assertEqual(rows['16341536244857936202']['placeId'],'poi/node/4033359736')
        self.assertEqual(rows['14602401179918739271']['placeId'],'poi/node/6354698707')
        self.assertEqual(rows['442926224695082437']['placeId'],'savvy/apple_maps/H2710I3F9AE050E2C28')
        self.assertEqual(rows['9401400014447048756']['placeId'],'poi/way/1053359244')
        for cid in ['1478576240692833592','6635082117113889489','10516715856781796735','11432354196742184079']:
            self.assertEqual(rows[cid]['placeId'],'creator/lala/'+cid)
        self.assertEqual(len({r['placeId'] for r in rows.values()}),280)

    def test_real_snapshot_accounts_for_every_place_and_post(self):
        data=json.loads((ROOT/'Prototypes/CreatorLists/lala/CreatorPlaceSources.json').read_text())
        rows=data['entries']+data['pending']
        self.assertEqual(len(rows),280)
        self.assertEqual(len(set(r['cid'] for r in rows)),280)
        self.assertEqual(sum('visited' in r['lists'] for r in rows),74)
        self.assertEqual(sum('wish' in r['lists'] for r in rows),248)
        self.assertEqual(sum(len(r['lists'])==2 for r in rows),42)
        self.assertEqual(sum(bool(r['posts']) for r in rows),41)
        self.assertEqual(sum(len(r['posts']) for r in rows),44)
        self.assertTrue(all(not set(r)&{'visitedAt','savedAt','note','verifiedAt','cover'} for r in rows))
        self.assertTrue(all(r['matchMethod'] in ('source_cid','reviewed_distinct_place') for r in data['entries'] if r['isNew']))
        self.assertEqual(data['pending'],[])
        self.assertEqual(data['summary']['attachedPostAssociations'],44)

if __name__ == '__main__':unittest.main()
