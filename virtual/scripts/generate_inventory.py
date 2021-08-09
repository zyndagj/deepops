#!/usr/bin/env python

import sys, os
from collections import defaultdict as dd

mfile = "machine_list.tsv"

mtypes = ('mgmt','login','gpu','cpu')
inventory = dd(list)

def main():
    if not os.path.exists(mfile):
        sys.exit("%s does not exist"%(mfile))
    # Parse machine list
    with open(mfile,'r') as IF:
        for line in IF:
            name, ip = line.rstrip('\n').split('\t')
            for t in mtypes:
                if t in name:
                    inventory[t].append((name,ip))
                    break
    # Write inventory
    with open('inventory','w') as OF:
        # Write ALL
        ostr = gen_heading("ALL NODES")
        for t in mtypes:
            for name, ip in inventory[t]:
                ostr += "%s ansible_host=%s ip=%s\n"%(name,ip,ip)
        OF.write(ostr+'\n')
        # Write kubernetes
        ostr = gen_heading("KUBERNETES")
        ostr += gen_section("kube-master", ("mgmt",))
        ostr += gen_section("etcd", ("mgmt",))
        ostr += gen_section("kube-node", ("gpu","cpu"))
        ostr += "[k8s-cluster:children]\nkube-master\nkube-node\n\n"
        OF.write(ostr)
        # Write slurm
        ostr = gen_heading("SLURM")
        ostr += gen_section("slurm-master",("login",))
        ostr += gen_section("slurm-node",("gpu","cpu"))
        ostr += "[slurm-cluster:children]\nslurm-master\nslurm-node\n\n"
        OF.write(ostr)
        # Write ssh
        ostr = gen_heading("SSH connection configuration")
        ostr += "[all:vars]\nansible_user=vagrant\nansible_password=vagrant\n"
        OF.write(ostr)

def gen_heading(text, n=10):
    fence = "#"*10
    return "%s\n# %s\n%s\n"%(fence, text, fence)

def gen_section(sname, type_list):
    rstr = '[%s]\n'%(sname)
    for t in type_list:
        for name, ip in inventory[t]:
            rstr += name+'\n'
    return rstr + '\n'
    
if __name__ == "__main__":
    main()
