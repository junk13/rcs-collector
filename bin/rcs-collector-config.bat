@echo off

set CWD=%CD%
cd /D C:\RCS\Collector

ruby bin\rcs-collector-config %*

cd /D %CWD%
