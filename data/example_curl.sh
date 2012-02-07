#!/bin/sh
curl -F "file=@/Users/stuartlynn/Sites/SETI/apps/Frank/data/test.bson;type=data/bson" -F "subject[activity_id]=1" -F "subject[observation_id]=1"  http://frank-seti.herokuapp.com/subjects
#curl -F "file=@/Users/stuartlynn/Sites/SETI/apps/Frank/test.bson;type=data/bson" -F "subject[activity_id]=1" -F "subject[observation_id]=1" -F "subject[source_id]=1" http://0.0.0.0:5000/subjects/
