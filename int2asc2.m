function y = int2asc2(a)

tmp = zeros(1,4);
a32 = dec2Bin(a,32);
tmp(1) = bin2Dec(a32(1:8));
tmp(2) = bin2Dec(a32(9:16));
tmp(3) = bin2Dec(a32(17:24));
tmp(4) = bin2Dec(a32(25:32));
y = char(tmp);