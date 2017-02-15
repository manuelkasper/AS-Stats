#!/usr/bin/env python
# (echo begin; echo verbose; for i in `seq 1 65535`; do echo "AS$i"; done; echo end) | netcat whois.cymru.com 43 | ./generate-asinfo.py > asinfo.txt

import sys

for line in sys.stdin:
	try:
		asn,country,_,_,data = [_.strip() for _ in line.split('|')]
	except ValueError:
		continue

	try:
		data,country = data.rsplit(',',1)
	except:
		data = data

	if data == '-Private Use AS-':
		data = 'Private Use AS'

	try:
		macro,name = data.split(' ',1)
	except:
		macro = data
		name = data

	if not (macro.count('-') or macro.upper() == macro or name.startswith('- ')) or macro == 'UK':
		macro = 'UNSPECIFIED'
		name = data

 	if name.startswith('- '):
		name = name[2:]

	print "%s\t%s\t%s\t%s" % (asn,macro,name,country)
