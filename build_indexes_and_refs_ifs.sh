#!/bin/bash

# Create indexes and refs for a single set of IFS forecast files.
# This should eventually be triggered when the last file of a forecast has been
# uploaded to PDS to the S3 bucket. And it should probably be rewritten in
# python too.
#
# Usage: ./build_indexes_and_refs_ifs.sh <analysis_time>
#   analysis_time: analysis time in ISO 8601 format (YYYY-MM-DDTHH:MM:SS)
#
# NB: for now we only process the first 12 hrs
#
# Running the script as for example:
#   ./build_indexes_and_refs_ifs.sh 2025-03-02T00:00
#
# Will result in the following GRIB files being indexed:
#   $ROOT_PATH/fc2025030200+000CONTROL__dmi_sf
#   $ROOT_PATH/fc2025030200+000CONTROL__dmi_pl
#   ...
#   $REFS_ROOT_PATH/fc2025030200+012CONTROL__dmi_sf
#   $REFS_ROOT_PATH/fc2025030200+012CONTROL__dmi_pl
#
# With the refs written as:
# refs/
# └── control/2025-03-02T0000Z.jsons
#     ├── adiabaticCondensation.json
#     ├── cloudTop.json
#     ├── entireAtmosphere.json
#     ├── freeConvection.json
#     ├── heightAboveGround.json
#     ├── heightAboveSea.json
#     ├── hybrid.json
#     ├── isobaricInhPa.json
#     ├── isothermal.json
#     ├── isothermZero.json
#     ├── neutralBuoyancy.json
#     ├── nominalTop.json
#     └── surface.json
#
# i.e. the "sf" and "pl" files are indexed and ref'ed into a single output directory


ANALYSIS_TIME=$1
ROOT_PATH="/dmidata/cache/mdcprd/gdb/grib2/ecmwf/glm/fc/"
REFS_ROOT_PATH="./refs/ifs/"

PROJECTION="ll"
DOMAIN="90000_-120000_000_90000_100_100"

if [ -z "$ANALYSIS_TIME" ]; then
    echo "usage: $0 <analysis_time> [temp_root]"
    echo "  analysis_time: analysis time in ISO 8601 format (YYYY-MM-DDTHH:MM:SSZ)"
    exit 1
fi

# set the temp root if it's provided
if [ -n "$2" ]; then
    TEMP_ROOT=$2
    COPY_GRIB_BEFORE_INDEXING=1
    mkdir -p $TEMP_ROOT
else
    COPY_GRIB_BEFORE_INDEXING=0
fi

# check that the analysis_time ends with Z so that we're sure it's UTC
if [[ ! $ANALYSIS_TIME =~ Z$ ]]; then
    echo "analysis_time must end with Z"
    exit 1
fi

# there are two types of files, ending with _sf and _pl, we need to index both
# files are stored as the following example:
# fc2025030206+042CONTROL__dmi_pl, i.e. the format is
# fc<analysis_time>+<forecast_hour><member_id>_<type>

# use `date` to format the analysis time to the format used in the file names
ANALYSIS_TIME_STR=$(date -d $ANALYSIS_TIME +%Y%m%d%H)

# check that the necessary GRIB files exist
# the files don't always arrive in order, so we need to check all of them
for type in sf ml; do
    for i in {00..12}; do
        #if [ ! -f "$ROOT_PATH/fc${ANALYSIS_TIME_STR}+0${i}${MEMBER_ID}_${type}" ]; then
        FILENAME="$ROOT_PATH/${type}/${PROJECTION}/${DOMAIN}/${ANALYSIS_TIME_STR}/0${i}"

        if [ ! -f "$FILENAME" ]; then
            echo "File $FILENAME does not exist"
            exit 1
        else
            echo "Found file $FILENAME"
        fi
    done
done

# Include $PWD/.ven/bin in PATH to ensure we use the right gribscan
export PATH="$PWD/.venv/bin/:$PATH"
echo $PATH
for type in sf ml; do
    SRC_PATH=""

    if [ $COPY_GRIB_BEFORE_INDEXING -eq 1 ]; then
        echo "Copying from $ROOT_PATH to $TEMP_ROOT/$type"
        # cp $ROOT_PATH/fc${ANALYSIS_TIME_STR}+0{00..01}${MEMBER_ID}_${type} $TEMP_ROOT
        # use rsync with --progress to show progress
        rsync -av --progress $ROOT_PATH/${type}/${PROJECTION}/${DOMAIN}/${ANALYSIS_TIME_STR}/0{00..12} $TEMP_ROOT/$type
        # check exist code and exit if not 0
        if [ $? -ne 0 ]; then
            echo "Failed to copy files"
            exit 1
        fi
        SRC_PATH=$TEMP_ROOT/$type
    else
        SRC_PATH=$ROOT_PATH
    fi

    echo "Indexing $type files"
    #gribscan-index $SRC_PATH/fc${ANALYSIS_TIME_STR}+0{00..12}${MEMBER_ID}_${type} -n 2
    #gribscan-index $SRC_PATH/${type}/${PROJECTION}/${DOMAIN}/${ANALYSIS_TIME_STR}/0${i} -n 2
    gribscan-index $SRC_PATH/0{00..12} -n 2

    echo "Building refs for $type files"
    gribscan-build $SRC_PATH/???.index \
         -o ${REFS_ROOT_PATH}/${ANALYSIS_TIME//:/}.jsons\
         --prefix $SRC_PATH/ \
         -m ifs
done
