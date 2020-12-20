import os
import sys
for r,d,f in os.walk(sys.argv[1]):
    for file in f:
        if file == 'Dockerfile':
            print(os.path.join(r, file)+ ': ' + open(os.path.join(r, file)).readline().rstrip().split(' ', 1)[1])
