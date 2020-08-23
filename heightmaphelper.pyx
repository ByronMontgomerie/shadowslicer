#cython: language_level=3
from cpython.exc cimport PyErr_CheckSignals

cdef class looper():
    cdef int mode
    cdef double x, y, py, offset, steps, h, w
    cdef bint zig,newrow
    
    def __init__(self, unsigned char [:, :] img, int mode, double offset, double steps):
        self.h = img.shape[0]
        self.w = img.shape[1]
        self.mode = mode
        self.offset = offset
        self.steps = steps
        self.x = offset
        self.y = offset
        self.zig = True
        self.newrow = False
        
    def __iter__(self):
        return self
        
    def __next__(self):
        cdef int pixel
        
        if ((self.mode & 2) == 2) and self.newrow:
            self.newrow = False
            self.y = self.py
        else: 
            if self.y > (self.h - self.offset - self.steps):
                raise StopIteration  
            else:
                
                if self.zig:
                    self.x = self.x + self.steps 
                    
                    if self.x >= (self.w - self.offset): 
                        
                        if (self.mode & 2) == 2:
                            self.py = self.y + self.steps 
                        else: 
                            self.y = self.y + self.steps
                            
                        if (self.mode & 1) == 1: 
                            self.zig = False
                            self.x = self.w - self.offset
                        else:
                            self.x = self.offset
                        
                        self.newrow = True
                else:
                    self.x = self.x - self.steps 
                    
                    if self.x <= self.offset:
                        
                        if (self.mode & 2) == 2:
                            self.py = self.y + self.steps
                        else: 
                            self.y = self.y + self.steps 
                            
                        if (self.mode & 1) == 1: 
                            self.zig = True
                            self.x = self.offset
                        else:
                            self.x = self.w - self.offset
                            
                        self.newrow = True
                
                if ((self.mode & 2) == 0) and (self.y > (self.h - self.offset - self.steps)):
                    raise StopIteration
        
        PyErr_CheckSignals()
                
        return self.x, self.y, self.newrow
        
cpdef void colourcount(unsigned char [:, :] img, dict hist):
    cdef int x, y, pixel
    cdef bint newrow
    
    for x, y, newrow in looper(img, 0, 0, 1):
        pixel = img[y, x]
        if format(pixel) in hist:
            hist[format(pixel)]= hist[format(pixel)] + 1    
        else:
            hist[format(pixel)] = 1
    
cpdef void update_image_from_layer(unsigned char [:, :] img, dict layers, int i, int overlap, bint swap):
    cdef int x, y
    cdef int j, pixel, npixel
    cdef bint newrow
  
    for x, y, newrow in looper(img, 0, 0, 1):
        
        j = i
        pixel = img[y,x]
        #print('x = ' + format(int(x)) + ' y = ' + format(int(y)) + ' pixel: ' + format(pixel))
        
        setp = 255 if swap else 0
        unsetp = 0 if swap else 255
        
        npixel = unsetp
        
        if overlap > 0:
            while format(j) in layers:
                if pixel in layers[format(j)]: 
                    npixel = setp
                    break
                j = (j - 1) if overlap == 1 else (j + 1)
        else:
            npixel = setp if  pixel in layers[format(i)] else unsetp

        try:
            img[y, x] = npixel
        except:
            break
            
cpdef str addline(str gcode, str line):
    return gcode + '\n' +line if len(gcode) > 0 else line

    
cpdef str addcmd(str gcode, str cmd, dict args):
    line = cmd
    for arg in args:
        line = line + ' ' + arg + format(args[arg], '0.2f')
    return addline(gcode, line)
            
cpdef str generate_gcode(unsigned char [:, :] img, str gcode, list feedrates, list zlevels, double toolwidth, double stepover, bint updownmode):

    cdef double x, y
    cdef bint newrow
    cdef int pixel, ix, iy
    cdef double fx, lx
    cdef int xyf, zuf, zdf
    cdef bint up, first, zigzag
    cdef double zclear, zsafe, z
    cdef list segments
    cdef double tipoffset
    
    xyf = feedrates[0]
    zuf = feedrates[1]
    zdf = feedrates[2]
    
    zclear = zlevels[0]
    zsafe = zlevels[1]
    z = zlevels[2]
    
    tipoffset = toolwidth / 2.0 
    
    lx = 0
    fx = 0

    up = True
    zigzag  = True
       
    segments = []
    steps = stepover
    
    print ('steps ' + format(steps, '0.2f'))
    
    for x, y, newrow in looper(img, 3, tipoffset, steps):
                    
        if not newrow:
            ix = int(x)
            iy = int(y)
            pixel = img[iy, ix]
            
            if pixel == 0:
                if up:
                    fx = x 
                    up = False
            else:
                if not up:
                    up = True
                    segments.append([fx , lx, y])                
            lx = x
        else:
            if not up:
                up = True
                segments.append([fx, lx , y]) 
            
    first = True
    
    for segment in segments:
        if updownmode:
            gcode = addcmd(gcode, 'g0', {'z' : zclear if first else zsafe, 'f' : zuf})
            gcode = addcmd(gcode, 'g1', {'x' : segment[0], 'y' : segment[2],'f' : xyf}) 
            gcode = addcmd(gcode, 'g1', {'z' : z, 'f' : zdf})
            gcode = addcmd(gcode, 'g1', {'x' : segment[1], 'y' : segment[2], 'z' : z, 'f' : xyf}) 
        else:
            if first: 
                gcode = addcmd(gcode, 'm3', {'s' : 0})
            gcode = addcmd(gcode, 'g1', {'x' : segment[0], 'y' : segment[2],'f' : xyf}) 
            gcode = addcmd(gcode, 'm3', {'s' : 255})
            gcode = addcmd(gcode, 'g1', {'x' : segment[1], 'y' : segment[2], 'f' : xyf}) 
            gcode = addcmd(gcode, 'm3', {'s' : 0})            
        first = False   
               
    return gcode
