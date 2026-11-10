# One-off generator of supabase/migrations/20261110210100_label_seed.sql (0A.12). Applied migrations never change:
# later label keys or default changes go in NEW migrations. Kept so the seed table stays readable and reviewable.
import sys
# key, group, animate, max, lockable, derived_from, legacy, description,
# product (en_s, en_p, bn), education (en_s, en_p, bn) or None = same as product
K = [
 ('lead','people',1,40,0,None,None,'A person who asked about an offering.',
   ('Lead','Leads','লিড'), None),
 ('client','people',1,40,0,None,'student','A person who converted (education: student).',
   ('Client','Clients','ক্লায়েন্ট'), ('Student','Students','শিক্ষার্থী')),
 ('contact_person','people',1,40,0,None,'guardian','A person responsible for or linked to a client.',
   ('Contact person','Contact persons','যোগাযোগকারী'), ('Guardian','Guardians','অভিভাবক')),
 ('network','people',1,40,0,None,'alumnus','Former clients kept in touch with.',
   ('Former client','Former clients','পুরোনো ক্লায়েন্ট'), ('Alumnus','Alumni','প্রাক্তন শিক্ষার্থী')),
 ('referrer','people',1,40,0,None,None,'A person who refers leads.',
   ('Referrer','Referrers','রেফারকারী'), None),
 ('offering','offering',0,30,0,None,'course','What the institution offers (education: course).',
   ('Service','Services','সেবা'), ('Course','Courses','কোর্স')),
 ('cohort','offering',0,30,0,None,'batch','A dated group of an offering (education: batch).',
   ('Session','Sessions','সেশন'), ('Batch','Batches','ব্যাচ')),
 ('slot_group','offering',0,30,0,None,'section','A sub-group inside a cohort (education: section).',
   ('Group','Groups','গ্রুপ'), ('Section','Sections','সেকশন')),
 ('branch','offering',0,30,0,None,None,'A campus, centre or office of the institution.',
   ('Branch','Branches','শাখা'), None),
 ('external_board','offering',0,30,0,None,None,'An outside body the conversion is registered with.',
   ('External authority','External authorities','বাইরের কর্তৃপক্ষ'), ('External board','External boards','বোর্ড')),
 ('board_id','offering',0,30,0,None,None,'The ID given by the external board.',
   ('External ID','External IDs','বাইরের আইডি'), ('Board ID','Board IDs','বোর্ড আইডি')),
 ('after_steps','conversion',0,30,0,None,'external_board_flow','Steps after conversion (education: board flow).',
   ('After step','After steps','পরের ধাপ'), ('Board flow','Board flows','বোর্ড ফ্লো')),
 ('conversion','conversion',0,30,0,None,'admission','The lead becomes a client (education: admission).',
   ('Enrolment','Enrolments','নিবন্ধন'), ('Admission','Admissions','ভর্তি')),
 ('converted','conversion',0,30,0,None,'admitted','Status: converted (education: admitted).',
   ('Enrolled','Enrolled','নিবন্ধিত'), ('Admitted','Admitted','ভর্তি হয়েছে')),
 ('conversion_cancelled','conversion',0,30,0,None,'admission_cancelled','Status: conversion cancelled.',
   ('Enrolment cancelled','Enrolment cancelled','নিবন্ধন বাতিল'), ('Admission cancelled','Admission cancelled','ভর্তি বাতিল')),
 ('lost','conversion',0,30,0,None,None,'Status: the lead was lost.',
   ('Lost','Lost','হাতছাড়া'), None),
 ('appointment','conversion',0,30,0,None,'campus_visit','A visit or meeting (education: campus visit).',
   ('Appointment','Appointments','অ্যাপয়েন্টমেন্ট'), ('Campus visit','Campus visits','ক্যাম্পাস ভিজিট')),
 ('assessment','conversion',0,30,0,None,'admission_test','A test or interview before conversion.',
   ('Assessment','Assessments','মূল্যায়ন'), ('Admission test','Admission tests','ভর্তি পরীক্ষা')),
 ('merit_list','conversion',0,30,0,None,None,'Published selection result.',
   ('Selection list','Selection lists','বাছাই তালিকা'), ('Merit list','Merit lists','মেধাতালিকা')),
 ('documents','conversion',0,30,0,None,'papers','Documents a client submits (education: papers).',
   ('Document','Documents','কাগজপত্র'), ('Paper','Papers','কাগজপত্র')),
 ('client_number','conversion',0,30,0,None,'student_id','The number given to a client (education: student ID).',
   ('Client ID','Client IDs','ক্লায়েন্ট আইডি'), ('Student ID','Student IDs','শিক্ষার্থী আইডি')),
 ('payment_plan','money',0,30,0,None,'fees_installments','Price and instalments of an offering.',
   ('Payment plan','Payment plans','পেমেন্ট প্ল্যান'), ('Fee plan','Fee plans','ফি ও কিস্তি')),
 ('fee','money',0,30,0,None,None,'An amount charged.', ('Fee','Fees','ফি'), None),
 ('installment','money',0,30,0,None,None,'One part of a payment plan.', ('Installment','Installments','কিস্তি'), None),
 ('receipt','money',0,30,0,None,None,'Proof of a payment.', ('Receipt','Receipts','রসিদ'), None),
 ('discount','money',0,30,0,None,None,'A reduction of a fee.', ('Discount','Discounts','ছাড়'), None),
 ('caller','roles',1,30,0,None,None,'Default name of the role template that calls leads.', ('Caller','Callers','কলার'), None),
 ('team_lead','roles',1,30,0,None,None,'Default name of the team supervisor role template.', ('Team Lead','Team Leads','টিম লিড'), None),
 ('conversion_officer','roles',1,30,0,None,'admission_officer','Default name of the role that completes conversions.',
   ('Enrolment Officer','Enrolment Officers','নিবন্ধন কর্মকর্তা'), ('Admission Officer','Admission Officers','ভর্তি কর্মকর্তা')),
 ('module.leads','modules',0,40,0,'lead','module.leads','Menu name of the leads module.', ('Leads','Leads','লিড'), None),
 ('module.clients','modules',0,40,0,'client','module.students','Menu name of the clients module.',
   ('Clients','Clients','ক্লায়েন্ট'), ('Students','Students','শিক্ষার্থী')),
 ('module.network','modules',0,40,0,'network','module.alumni','Menu name of the network module.',
   ('Former clients','Former clients','পুরোনো ক্লায়েন্ট'), ('Alumni','Alumni','প্রাক্তন শিক্ষার্থী')),
 ('module.conversion_contribution','modules',0,28,0,None,'module.admission_contribution','Menu name: conversion contribution.',
   ('Enrolment Contribution','Enrolment Contribution','নিবন্ধনে অবদান'), ('Admission Contribution','Admission Contribution','ভর্তিতে অবদান')),
 ('module.conversion_flow','modules',0,28,0,None,'module.admission_flow','Menu name: steps of a conversion.',
   ('Enrolment flow','Enrolment flow','নিবন্ধনের ধাপ'), ('Admission flow','Admission flow','ভর্তির ধাপ')),
 ('module.leaderboard','modules',0,28,0,None,None,'Menu name of the leaderboard.', ('Leaderboard','Leaderboard','লিডারবোর্ড'), None),
 ('module.scorecard','modules',0,28,0,None,None,'Menu name of the weekly scorecard.', ('Weekly scorecard','Weekly scorecard','সাপ্তাহিক স্কোরকার্ড'), None),
 ('module.referrals','modules',0,28,0,None,None,'Menu name of the referral inbox.', ('Referral inbox','Referral inbox','রেফারেল ইনবক্স'), None),
 ('doc.receipt_title','documents',0,40,1,None,None,'Title printed on receipts.', ('Money Receipt','Money Receipts','মানি রসিদ'), None),
 ('doc.admit_card_title','documents',0,40,1,None,None,'Title printed on entry cards.', ('Entry Pass','Entry Passes','প্রবেশপত্র'), ('Admit Card','Admit Cards','প্রবেশপত্র')),
 ('doc.application_form_title','documents',0,40,1,None,None,'Title of the public application form.', ('Application Form','Application Forms','আবেদন ফর্ম'), None),
 ('doc.id_card_title','documents',0,40,1,None,None,'Title printed on ID cards.', ('ID Card','ID Cards','পরিচয়পত্র'), None),
]
# Ch 8.5 per-type examples (profile defaults; wired to type profiles in 0B).
P = {
 'school': {'offering':('Class','Classes','শ্রেণি'),'cohort':('Session','Sessions','সেশন'),'client_number':('Roll','Rolls','রোল'),'lead':('Enquiry','Enquiries','জিজ্ঞাসা')},
 'university': {'offering':('Program','Programs','প্রোগ্রাম'),'cohort':('Intake','Intakes','ইনটেক'),'lead':('Applicant','Applicants','আবেদনকারী'),'conversion':('Enrolment','Enrolments','ভর্তি')},
 'polytechnic': {'offering':('Technology','Technologies','টেকনোলজি'),'cohort':('Session','Sessions','সেশন'),'slot_group':('Group','Groups','গ্রুপ'),'client_number':('Roll','Rolls','রোল'),'lead':('Applicant','Applicants','আবেদনকারী')},
}
q = lambda s: 'null' if s is None else "'" + s.replace("'", "''") + "'"
animate = {k[0]: bool(k[2]) for k in K}
out = ["-- 0A.12-T2 Seed: every Ch 8.4 key with English and Bangla defaults (generated by scripts/labels/gen_label_seed_0A12.py).",
       "-- product = neutral words for any business; pack 'education' = Ch 8.4 defaults (D20); profiles = Ch 8.5 examples.",
       "insert into public.label_keys (key, label_group, animate, max_length, lockable, derived_from, legacy_key, description, sort_order) values"]
rows = []
for i,k in enumerate(K):
    rows.append(f"  ({q(k[0])}, {q(k[1])}, {'true' if k[2] else 'false'}, {k[3]}, {'true' if k[4] else 'false'}, null, {q(k[6])}, {q(k[7])}, {i*10})")
out.append(",\n".join(rows) + ";")
derived = [k for k in K if k[5]]
for k in derived:
    out.append(f"update public.label_keys set derived_from = {q(k[5])} where key = {q(k[0])};")
def ins(scope, scope_key, key, t):
    return f"  ({q(scope)}, {q(scope_key)}, {q(key)}, {q(t[0])}, {q(t[1])}, app.bn_forms({q(t[2])}, {'true' if animate[key] else 'false'}))"
out.append("insert into public.label_defaults (scope, scope_key, key, en_singular, en_plural, bn_forms) values")
rows = [ins('product','',k[0],k[8]) for k in K]
rows += [ins('pack','education',k[0],k[9] or k[8]) for k in K]
for prof, m in P.items():
    rows += [ins('profile',prof,key,t) for key,t in m.items()]
out.append(",\n".join(rows) + ";")
open(sys.argv[1],'w').write("\n".join(out) + "\n")
print(len(K), "keys")
