from datetime import datetime, timedelta
from sqlite3 import Timestamp
import sys
import time
import gc
import os
import glob

from labjack import ljm

# from labjack.ljm import constants as ljmc
# ljmc.STREAM_AIN_BINARY = 0


# print('#x,y,z',file=f)
# print('x,y,z', file=f)   #csv파일 헤더

boot_time = datetime.now()
boot_time_delta = boot_time - timedelta(days=1)

try:
    [os.remove(b) for b in glob.glob('stream%s_*.csv' %(boot_time_delta.day))]
except OSError:
    pass

MAX_REQUESTS = 172800

handle = ljm.openS("T7","USB","ANY")

info = ljm.getHandleInfo(handle)
deviceType = info[0]

aScanListNames = ["AIN0","AIN1","AIN2","AIN3","AIN4","AIN5"]
numAddresses = len(aScanListNames)
aScanList = ljm.namesToAddresses(numAddresses, aScanListNames)[0]
scanRate = 5000
scansPerRead = int(scanRate / 2)

try:
    if deviceType == ljm.constants.dtT4:
        aNames = ["AIN0_RANGE", "AIN1_RANGE", "STREAM_SETTLING_US",
                  "STREAM_RESOLUTION_INDEX"]
        aValues = [10.0, 10.0, 0, 0]
    else:
        ljm.eWriteName(handle, "STREAM_TRIGGER_INDEX", 0)
        ljm.eWriteName(handle, "STREAM_CLOCK_SOURCE", 0)

        aNames = ["AIN_ALL_NEGATIVE_CH", "AIN0_RANGE", "AIN1_RANGE", "AIN2_RANGE", "AIN3_RANGE", "AIN4_RANGE", "AIN5_RANGE", "STREAM_SETTLING_US", "STREAM_RESOLUTION_INDEX"]
        aValues = [ljm.constants.GND, 10.0, 10.0 ,10.0, 10.0, 10.0, 10.0, 0, 0]

    numFrames = len(aNames)
    ljm.eWriteNames(handle, numFrames, aNames, aValues)
    
    scanRate = ljm.eStreamStart(handle, scansPerRead, numAddresses, aScanList, scanRate)
    
    start = datetime.now()
    print(start)

    totScans = 0
    totSkip = 0

    ttimer = 0
    i = 1

    while i <= MAX_REQUESTS:
        gc.collect()
        ss = datetime.now()
        delta = ss - timedelta(hours=1)
        
        try:
            os.remove('/media/pi/SAMSUNG/csv/stream{}_{}_{}_{}_{}.csv'.format(ss.strftime('%Y'), ss.strftime('%m'), ss.strftime('%d'), ss.strftime('%H'), ss.strftime('%M')))
        except OSError:
            pass
        
        f = open('/media/pi/SAMSUNG/csv/stream{}_{}_{}_{}_{}.csv'.format(ss.strftime('%Y'), ss.strftime('%m'), ss.strftime('%d'), ss.strftime('%H'), ss.strftime('%M')), 'a+')
        #print (f.tell())
   
        ret = ljm.eStreamRead(handle)
        
        data = ret[0][0:(scansPerRead * numAddresses)]
        scans = len(data) / numAddresses
        totScans += scans

        curSkip = data.count(-9999.0)
        totSkip += curSkip

        #print("\neStreamRead #%i, %i scans" % (i, scans))
        if f.tell() == 0 :
            readStr = "moter_x,moter_y,moter_z,pump_x,pump_y,pump_z,time"+"\n"
        else:
            readStr = ""
        ttt = time.time()
        timer = 0
        for j in range(0, scansPerRead):
            for k in range(0, numAddresses):
                readStr += "%f," % (data[j * numAddresses + k])
            #readStr += "%f" % (j*(1/scanRate))
            timer += (1/scanRate)
            readStr += "%s" % (datetime.fromtimestamp(ttt + (ttimer + timer)).isoformat("T") + "Z")
            readStr += "\n"
        #print(readStr)
        print(readStr, file=f, end="")

        ttimer += timer
        i += 1

    end = datetime.now()

    tt = (end - start).seconds + float((end - start).microseconds) / 1000000
    print("Timed Sample Rate = %f samples/second" % (totScans * numAddresses/tt))

except ljm.LJMError:
    ljme = sys.exc_info()[1]
    print(ljme)
except Exception:
    e = sys.exc_info()[1]
    print(e)

try:
    print("\nStop Stream")
    ljm.eStreamStop(handle)
except ljm.LJMError:
    ljme = sys.exc_info()[1]
    print(ljme)
except Exception:
    e = sys.exc_info()[1]
    print(e)

#print("Start Time :" , start , "," , "Finish Time :" , end , "," , "The time required :" , (end - start))

# Close handle
ljm.close(handle)
