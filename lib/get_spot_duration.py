#!/usr/bin/env python2.7
# Copyright 2015 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License"). You may not use this file except in compliance with the
# License. A copy of the License is located at
#
# http://aws.amazon.com/asl/
#
# or in the "LICENSE.txt" file accompanying this file. This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES
# OR CONDITIONS OF ANY KIND, express or implied. See the License for the specific language governing permissions and
# limitations under the License.
#
# ---------------------------------------------------------------------------------------------------------------------
# get_spot_duration.py uses AWS CLI tools to obtain price history for the last week (by default), 
# and prints time duration since the last time Spot price exceeded the bid price.
# 
# We use CLI for simplicity and demonstration purposes. For production code please use SDK/boto3
# Input: product-description, region, and combination of instance types and Spot bids prices for each instance type.
# Example:
# $ python get_spot_duration.py -r us-east-1 -b c3.large:0.105,c3.xlarge:0.210 \
#    --product-description 'Linux/UNIX (Amazon VPC)'
#
# v0.1
import argparse
from argparse import RawTextHelpFormatter
import calendar
import json
import sys
import datetime
import time, os
from subprocess import Popen, PIPE

# Call AWS CLI and obtain JSON output, we could've also used tabular or text, but json is easier to parse.
def make_call(cmdline, profile):
    cmd_args = ['aws', '--output', 'json'] + (['--profile', profile] if profile else []) + cmdline
    #print " ".join(cmd_args)
    p = Popen(cmd_args, stdout=PIPE)
    res, _ = p.communicate()
    if p.wait() != 0:
        sys.stderr.write("Failed to execute: " + " ".join(cmd_args))
        sys.exit(1)
    if not res:
        return {}
    return json.loads(res)


def iso_to_unix_time(iso):
    return calendar.timegm(time.strptime(iso, '%Y-%m-%dT%H:%M:%S.%fZ'))

# For each availability zone, return timestamp of the last time Spot price exceeded specified bid price
def get_last_spot_price_exceeding_the_bid(profile, hours, inst_type, region, product, bid,env):
    now = datetime.datetime.utcfromtimestamp(time.time())
    start_time = now - datetime.timedelta(hours=hours)
    start_time_unix = calendar.timegm(start_time.utctimetuple())
    vPriceHistoryData='/tmp/qucikawsspothistory_' + region + '_' + inst_type + '_' + str.replace(product,'/','') + '_' + env + '_' +  str(hours) + '.json'  
    if os.path.isfile(vPriceHistoryData) and datetime.datetime.now() - datetime.datetime.fromtimestamp(os.stat(vPriceHistoryData).st_ctime) <= datetime.timedelta(minutes=10):
        print "Reading existing spot history data"
        f = open(vPriceHistoryData,'r+')
        res = json.load(f)
    else:    
        #: :type: list of SpotPriceHistory
        res = make_call(["ec2", "--region", region,
                         "describe-spot-price-history",
                         "--start-time", start_time.isoformat(),
                         "--end-time", now.isoformat(),
                         "--instance-types", inst_type,
                         "--product-descriptions", product], profile)
        
        f = open(vPriceHistoryData,'w+')
        json.dump(res,f)
        f.close()
        print 'Price history written at ' + vPriceHistoryData

    last_times = {}
    for p in res['SpotPriceHistory']:
        cur_ts = iso_to_unix_time(p['Timestamp'])
        cur_az = p['AvailabilityZone']
        if (inst_type, cur_az) in last_times:
            old_ts = last_times.get((inst_type, cur_az))[0]
            last_times[(inst_type, cur_az)][3]=last_times[(inst_type, cur_az)][3]+1 #count
        else:
            old_ts = None    

        if old_ts is None:
            last_times[(inst_type, cur_az)] = []
            old_ts = start_time_unix
            last_times[(inst_type, cur_az)].append(old_ts)
            last_times[(inst_type, cur_az)].append(float(p['SpotPrice']))
            last_times[(inst_type, cur_az)].append(p['Timestamp'])
            last_times[(inst_type, cur_az)].append(1) #count

        if float(p['SpotPrice']) > bid and cur_ts > old_ts:
            last_times[(inst_type, cur_az)][0] = cur_ts

    return last_times


parser = argparse.ArgumentParser(
    formatter_class=RawTextHelpFormatter,
    description="get_spot_duration.py - order capacity pools based on duration since the last time"
                "or current price or most recent request or total number of request.",
    epilog="Output: tab-separated list of (duration_in_hours, instance_type, availability_zone) tuples\n\n"
           "Example:\n"
           "./get_spot_duration.py -r us-east-1 -b c3.large:0.105,c3.xlarge:0.210 \ \n"
           "    --product-description 'Linux/UNIX (Amazon VPC)'")
parser.add_argument("-r", "--region", help="AWS region (e.g.: us-east-1)", dest="region", required=True)
parser.add_argument("--profile", help="AWS CLI tools profile", dest="profile", default=None)
parser.add_argument("--hours", dest="hours", type=int, default=7*24, help="The period to check, in hours. Default is 1 week.")

product_choices = ["Linux/UNIX", "SUSE Linux", "Windows",
                   "Linux/UNIX (Amazon VPC)", "SUSE Linux (Amazon VPC)",
                   "Windows (Amazon VPC)"]
sort_by_choices = ['VolatalityDuration','CurrentPrice','MostRecentRequestTime','NumberOfRequest']

parser.add_argument("--product-description","-p", help='EC2 Product Type in double quotes (e.g.: "Linux/UNIX (Amazon VPC)")', type=str,
                    choices=product_choices, dest="product")

parser.add_argument("--bids", "-b",help="Comma-separated list of instance types and bids:  Instance_type:bid,"
                    "    example: c3.2xlarge:1,c3.4xlarge:2", required=True, dest="list_of_spot_bids")
parser.add_argument("--sort-by","-s", help='Output result sort in descending order by CurrentPrice/VolatalityDuration/MostRecentRequestTime/NumberOfRequest', type=str,
                    choices=sort_by_choices, dest="sort_by",default='CurrentPrice')
parser.add_argument("--env","-e", help='Environment (dev/qa/prod)', type=str,
                    choices=['dev','qa','prod'], dest="env",default='dev')


args = parser.parse_args()

if args.product is None:
    sys.stderr.write("No product specified out of the list of supported options: %s\n" % (", ".join(product_choices)))
    sys.exit(1)


types = {}
for it in args.list_of_spot_bids.split(","):
    parts = it.split(":")
    if len(parts) != 2:
        sys.stderr.write("Instance type '%s' is malformed. It needs to include "
                         "instance type and bid, e.g. c3.2xlarge:1.0\n" % it)
        sys.exit(1)

    try:
        types[parts[0]] = float(parts[1])
    except TypeError:
        sys.stderr.write("Price '%s' is malformed, should be a floating point number.\n" % parts[1])
        sys.exit(1)

result = {}
for it, bid in types.items():
    result.update(get_last_spot_price_exceeding_the_bid(args.profile, args.hours, it, args.region, args.product, bid, args.env))
unix_now = time.time()

sorted_result =sorted(result.keys(), key=lambda k: result[k][sort_by_choices.index(args.sort_by)], reverse=False)

print "DurationHour,InstanceType,AvailabilityZone,CurrentPrice,MostRecentRequest,TotalRequests"
for key in sorted_result:
    value=result[key]
    date = value[0]
    #volatilityDurationHour=(unix_now - date)/3600.0
    #if volatilityDurationHour > 6.0:
#    print "%8.1f,%s,%-16s,%11.5f,%s,%d" % ((unix_now - date)/3600.0, key[0], key[1],value[1],value[2],value[3])
    print "%.1f,%s,%s,%.5f,%s,%d" % ((unix_now - date)/3600.0, key[0], key[1],value[1],value[2],value[3])

'''
Example output:
DurationHour    InstanceType    AvailabilityZone    CurrentPrice    MostRecentRequest   TotalRequests
    10.0    r3.2xlarge  us-east-1c              0.10840 2016-10-15T06:02:10.000Z    1389
    10.0    r3.2xlarge  us-east-1a              0.11070 2016-10-15T06:02:10.000Z    1363
    10.0    r3.2xlarge  us-east-1b              0.12600 2016-10-15T06:02:10.000Z    1371
     4.4    r3.2xlarge  us-east-1e              0.21200 2016-10-15T06:02:10.000Z    1239
'''     

#result_new=sorted(result.items(), key=lambda e: e[2][1][0])
#print result_new
#print "Duration\tInstanceType\tAvailabilityZone\tCurrentPrice\tMostRecentRequest\tTotalRequests"
#for key, value in result.iteritems():
#    date = value[0]
#    print "%8.1f\t%s\t%-16s\t%11.5f\t%s\t%d" % ((unix_now - date)/3600.0, key[0], key[1],value[1],value[2],value[3])
