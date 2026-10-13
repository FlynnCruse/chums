#!/usr/bin/env python3
"""Print the Apple developer team to sign Chums with.

Order: $CHUMS_TEAM, then a paid team from Xcode's account cache, then the team (OU) of a valid Apple Development
certificate in the keychain that isn't a free team's, then a free Personal Team (free provisioning: installs on your
own devices expire after 7 days). Prints nothing if none is found; prints "free" on stderr when it picks a free team."""
import os, plistlib, re, subprocess, sys

if os.environ.get('CHUMS_TEAM'):
    print(os.environ['CHUMS_TEAM']); sys.exit()

try:
    prefs = plistlib.loads(subprocess.run(['defaults', 'export', 'com.apple.dt.Xcode', '-'], capture_output=True).stdout)
    # IDEProvisioningTeamByIdentifier is what each signed-in account can use now (empty while a team is suspended or
    # being converted); IDEProvisioningTeams can still list teams an account has lost
    live = prefs.get('IDEProvisioningTeamByIdentifier')
    if live is not None:
        teams = [t for ts in live.values() for t in ts if isinstance(t, dict)]
    else:
        teams = [t for ts in prefs.get('IDEProvisioningTeams', {}).values() for t in ts]
    paid = [t for t in teams if not t.get('isFreeProvisioningTeam') and t.get('teamID')]
    # prefer a team you run (Admin / Agent) over one where you're only a member
    paid.sort(key=lambda t: 0 if str(t.get('teamMemberRole', '')).lower() in ('admin', 'agent', 'account holder') else 1)
    if paid:
        print(paid[0]['teamID']); sys.exit()
    free = [t['teamID'] for t in teams if t.get('isFreeProvisioningTeam') and t.get('teamID')]
except Exception:
    free = []

pems = subprocess.run(['security', 'find-certificate', '-a', '-c', 'Apple Development', '-p'], capture_output=True, text=True).stdout
certs = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', pems, re.S)
best = None
for pem in certs:
    # a valid Apple Development certificate of a team that isn't a free Personal Team (e.g. a team that just became an
    # organization, whose account Xcode's cache may not list yet)
    if subprocess.run(['openssl', 'x509', '-noout', '-checkend', '0'], input=pem, capture_output=True, text=True).returncode != 0:
        continue
    out = subprocess.run(['openssl', 'x509', '-noout', '-subject'], input=pem, capture_output=True, text=True).stdout
    ou = re.search(r'OU\s*=\s*([A-Z0-9]{10})', out)
    if ou and ou.group(1) not in free:
        best = ou.group(1)
if best:
    print(best); sys.exit()

# no paid team and no valid certificate: a free Personal Team still signs for your own devices (7-day installs)
if free:
    print('free', file=sys.stderr); print(free[0])
