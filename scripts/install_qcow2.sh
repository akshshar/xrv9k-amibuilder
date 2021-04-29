#!/bin/bash

img=`ls /mnt/*.qcow2*`
img_base=$(basename $img)
img_ext="${img_base##*.}"


if [ "$img_ext" = "qcow2" ]; then
    qcow2=$img
elif [ "$img_ext" = "tar" ]; then
    qcow2=`tar tf $img`
    qcow2="/mnt/$qcow2"
    tar xvf $img -C /mnt && rm $img
else
    echo "the xrv9k image $img_base is not in supported format"
    exit 1
fi

qemu-img convert -O raw $qcow2 /mnt/image.raw 2>&1
dd conv=sparse if=/mnt/image.raw of=/dev/xvdc bs=1M 2>&1
sync
sleep 30
