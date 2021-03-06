#	Script with functions for calculating GII, CAAI and CINdex in breast cancer data
# original link: https://github.com/arnevpladsen/CARMA
#	Author: Arne Pladsen
#revised by :Chen Shangying, revised date: 29/01/2021
#change the input from segment.list to segment data frame with 6 columns
##input segment
#6 columns: SampleName, chr, startpos, endpos, nMajor, nMinor


library(dplyr)
library(magrittr)
library(carma)

###################################################################
##	GII
###################################################################
calculateGII = function(segment, hg=hg38, exclude.x.chrom=F){
  res = as.data.frame(unique(segment$SampleName))
  res %<>% set_colnames(c("SampleName")) %>% distinct() %>% mutate(GII= "na")
  res %<>% as.matrix()
  for(i in 1:nrow(res)) {
    sample = res[i, 1]
    seg = segment %>% filter(SampleName %in% sample)
    seg = carma:::continuousSegments(seg, hg, exclude.x.chrom)
    cent = carma:::center(seg)
    tot.length = sum(seg$endpos-seg$startpos)
    dev.seg = seg[!seg$nMajor + seg$nMinor == cent, ]
    dev.length = sum(dev.seg$endpos-dev.seg$startpos)
    res[i, 2] = round(dev.length/tot.length, 3)
  }
  return(res)
}

###################################################################
##	CAAI
###################################################################
calculateCAAI = function(segment, hg=hg38, exclude.x.chrom=F){
  n.samples = length(unique(segment$SampleName))
  samp.names = unique(segment$SampleName)
  test.segment = segment %>% filter(SampleName %in% samp.names[1])
  test.seg = carma:::continuousSegments(test.segment, hg, exclude.x.chrom)
  regs = unique(test.seg$arm)
  res.mat = as.data.frame(matrix(NA, nrow=length(regs),
                                 ncol=n.samples, dimnames=list(regs, samp.names)))
  for(i in 1:n.samples){
    if(i %in% seq(1,2000,10)){print(paste("Sample", i))}
    seg = segment %>% filter(SampleName %in% samp.names[i])
    seg = carma:::continuousSegments(seg, hg, exclude.x.chrom)
    for(j in 1:length(regs)){
      tmp.seg = seg[which(seg$arm==regs[j]), ]
      input.seg = data.frame(	start.pos=tmp.seg$startpos,
                              end.pos=tmp.seg$endpos,
                              mean=log2(tmp.seg$nMajor+tmp.seg$nMinor+1))
      input.seg = collapseLRRSegments(input.seg)
      tmp.caai = findCAAI(input.seg$start.pos, input.seg$end.pos,
                          input.seg$mean)
      res.mat[j,i] = log2(tmp.caai+1)
    }
  }
  colnames(res.mat) = samp.names
  return(res.mat)
}

#	Function to merge neighbouring segments with same total copy number.
#	The function is called by calculate.CAAI


collapseLRRSegments = function(seg) {
  if (nrow(seg)>1) {
    d = diff(seg$mean)
    if (any(d==0)) {
      j=1
      for(i in 1:length(d)){
        if (d[i]==0) {
          seg$end.pos[j] = seg$end.pos[j+1]
          seg = seg[-(j+1),]
        } else {
          j = j+1
        }
      }
    }
  }
  seg$seg.length = seg$end.pos-seg$start.pos+1
  return(seg)
}

# 	The base CAAI algorithm. The function is called by calculate.CAAI
findCAAI = function(startPos, stopPos, height) {
  if (length(startPos) != length(stopPos)) {
    stop("Error: startPos and stopPos should be vectors of equal length.")
  } else if (length(startPos) < 3) {
    return (0)
  }
  alpha = 10000 / 0.005
  beta0 = 1 / 1.2
  winwidth = 2 * 10^7
  nseg = length(startPos)
  L = rep(0,nseg)
  L[1] = (stopPos[1]+startPos[2])/2 - startPos[1]
  L[nseg] = stopPos[nseg] - (stopPos[nseg-1] + startPos[nseg])/2
  for (i in 2:(nseg-1)) {
    L[i] = (stopPos[i] + startPos[i+1])/2 - (stopPos[i-1] +
                                               startPos[i])/2
  }
  x = rep(0,nseg-1)
  P = rep(0,nseg-1)
  Q = rep(0,nseg-1)
  W = rep(0,nseg-1)
  S = rep(0,nseg-1)
  for (i in 1:(nseg-1)) {
    x[i] = (stopPos[i] + startPos[i+1])/2
    P[i] = tanh(alpha / (L[i] + L[i+1]))
    Q[i] = tanh(beta0 * abs(height[i] - height[i+1]))
    W[i] = 0.5 * (1 + (tanh(10*(P[i] - 0.5)) / tanh(5)))
    S[i] = W[i] * min(P[i], Q[i])
  }
  cai = 0
  for (first in 1:(nseg-2)) {
    last = first
    while (last < nseg-1 && x[last+1]-x[first] <= winwidth) {
      last = last + 1
    }
    cai = max(cai, sum(S[first:last]))
  }
  return(cai)
}


###################################################################
##	CINdex
###################################################################
calculateCINdex = function(segment, hg=hg38, exclude.x.chrom=F){
  n.samples = length(unique(segment$SampleName))
  samp.names = unique(segment$SampleName)
  test.segment = segment %>% filter(SampleName %in% samp.names[1])
  test.seg = carma:::continuousSegments(test.segment, hg,
                                        exclude.x.chrom)
  regs = unique(test.seg$arm)
  res.mat = as.data.frame(matrix(NA, nrow=length(regs),
                                 ncol=n.samples, dimnames=list(regs, samp.names)))
  length.tab = data.frame(region=paste0(hg$chr, "_", hg$arm),
                          length=hg$endpos-hg$startpos+1)
  #create an empty list
  segment.list <- vector(mode="list", length=n.samples)
  names(segment.list) <- samp.names
  for(i in 1:n.samples){
    seg = segment %>% filter(SampleName %in% samp.names[i])
    seg = carma:::continuousSegments(seg, hg, exclude.x.chrom)
    ploidy = carma:::center(seg)
    seg$norm.mean = (seg$nMajor+seg$nMinor)/ploidy
    segment.list[[i]] = seg
  }
  A = max(unlist(lapply(segment.list, function(x) max(x$norm.mean,
                                                      na.rm=T))), na.rm=T)
  for(i in 1:n.samples){
    if(i %in% seq(1,2000,10)){print(paste("Sample", i))}
    seg = segment.list[[i]]
    for(j in 1:length(regs)){
      tmp.seg = seg[which(seg$arm==regs[j]), ]
      if(nrow(tmp.seg) == 0){next}
      N = length.tab$length[match(regs[j], length.tab$region)]
      tmp.seg$score = 0
      tmp.seg$score = ifelse(tmp.seg$norm.mean>1,
                             tmp.seg$norm.mean-1, tmp.seg$score)
      tmp.seg$score = ifelse(tmp.seg$norm.mean<1,
                             abs(1-tmp.seg$norm.mean)*(A-1), tmp.seg$score)
      tmp.seg$length = tmp.seg$endpos-tmp.seg$startpos + 1
      res.mat[j,i] = sum(tmp.seg$score*tmp.seg$length/N, na.rm=T)
    }
  }
  return(res.mat)
}
