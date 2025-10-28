#!/bin/bash

export system=$(basename $(echo $HOME))

module load fsl

# add python to path
export PATH=${PATH}://N/slate/jfaskowi/miniconda3/bin
pybin=/N/slate/jfaskowi/miniconda3/bin/python

module unload python

# setup my stuffs
source $HOME/myfunctions.sh
source $HOME/log.sh

####################################################################
####################################################################

scans_7T_MOVIE="tfMRI_MOVIE1_7T_AP tfMRI_MOVIE2_7T_PA tfMRI_MOVIE3_7T_PA tfMRI_MOVIE4_7T_AP"
scans_7T_REST="rfMRI_REST1_7T_PA rfMRI_REST2_7T_AP rfMRI_REST3_7T_PA rfMRI_REST4_7T_AP"

#184
SUBJECT=($(cat /N/project/HCPaging/josh_sandbox/hcp7t/download/subjects.txt))

if [[ -z ${CMDLINE_IND} ]] ; then
    subj=${SUBJECT[${SLURM_ARRAY_TASK_ID:-$1}-1]}
else
    subj=${SUBJECT[${CMDLINE_IND}-1]}
fi
[[ -z ${subj} ]] && { echo "subj variable empty" ; exit 1 ; }


echo ${subj} 
>&2 echo ${subj} 

workingDir=/N/scratch/jfaskowi/hcp/func7t/regressors/${subj}/
mkdir -p $workingDir

#go into the folder where the script should be run
cd $workingDir
echo "CHANGING DIRECTORY into $workingDir"

OUT=notes.txt
touch $OUT
PRINT_LOG_HEADER_DUDE $OUT

start=`date +%s`

#############################################################################
# makea mask

iHcpDir=/N/dcwan/projects/hcp/${subj}/MNINonLinear/

# first, we need to generate a global mask, wm mask, and gm mask and resample to
# 1.6^3, which is voxel size of nifti image 
# also need to make sure we using the MNI nonlinear vol

WM_ROI=${iHcpDir}/ROIs/WMReg.1.60.nii.gz
CSF_ROI=${iHcpDir}/ROIs/CSFReg.1.60.nii.gz

# make the global roi
initBrain=${iHcpDir}/brainmask_fs.nii.gz
cmd="${FSLDIR}/bin/flirt \
		-in $initBrain \
		-ref $initBrain \
		-out ${workingDir}/brainmask_1p6.nii.gz \
		-applyisoxfm 1.6 \
	"
echo $cmd 
eval $cmd
cmd="${FSLDIR}/bin/fslmaths \
		${workingDir}/brainmask_1p6.nii.gz \
		-thr 0.99 -bin \
		${workingDir}/brainmask_1p6.nii.gz \
	"
echo $cmd 
eval $cmd
GLOBAL_ROI=${workingDir}/brainmask_1p6.nii.gz

#############################################################################
# BIG LOOOOOOOOOOOP

for TTT in 7T_MOVIE 7T_REST ; do

#############################################################################
# first unzip ish

iZipDir=/N/project/HCPaging/josh_sandbox/hcp7t/download/

# zipFile=${iZipDir}/${subj}_7T_MOVIE_2mm_fix.zip
# unzip -n ${zipFile} -d ${workingDir}/ '*MSMAll*'

zipFile=${iZipDir}/${subj}_${TTT}_2mm_preproc.zip
unzip -n ${zipFile} -d ${workingDir}/ '*txt'
# unzip -n ${zipFile} -d ${workingDir}/ '*nii'
unzip -n ${zipFile} -d ${workingDir}/ '*brainmask_fs.1.60.nii.gz'

# zipFile=${iZipDir}/${subj}_${SSS}_preproc_extended.zip
# unzip -n ${zipFile} -d ${workingDir}/ '*PA.nii.gz'
# unzip -n ${zipFile} -d ${workingDir}/ '*AP.nii.gz'

iDir=${workingDir}/${subj}/MNINonLinear/Results/


loopover="scans_${TTT}" 
for SSS in ${!loopover} ; do

	oDir=${workingDir}/${SSS}/
	mkdir -p ${oDir}

	# # get rid of the dtseries you know you don't need
	# ls ${iDir}/${SSS}/${SSS}_Atlas.dtseries.nii && rm ${iDir}/${SSS}/${SSS}_Atlas.dtseries.nii

	echo "processing $SSS"

	zipFile=${iZipDir}/${subj}_${TTT}_preproc_extended.zip
	unzip -n ${zipFile} -d ${workingDir}/ '*'${SSS}'.nii.gz'

	# ############################################################################
	# # vars

	MNINonLinearFunc=${iDir}/${SSS}/${SSS}.nii.gz
	for xxx in CSF WM GLOBAL ; do

		echo "WORKING ON $xxx trace"

		roimask=${xxx}_ROI

		# need to make global trace with fslmeants
		cmd="${FSLDIR}/bin/fslmeants \
				-i ${MNINonLinearFunc} \
				-o ${oDir}/${SSS}_${xxx}.txt \
				-m ${!roimask} \
			"
		echo $cmd
		[[ ! -e ${oDir}/${SSS}_${xxx}.txt ]] && eval $cmd

		if [[ $xxx = "GLOBAL" ]] ; then continue ; fi

		cmd="${FSLDIR}/bin/fslmaths \
				${MNINonLinearFunc} \
				-mas ${!roimask} \
				${oDir}/${SSS}_${xxx}_func.nii.gz \
			"
		echo $cmd
		[[ ! -e ${oDir}/${SSS}_${xxx}_func.nii.gz ]] && eval $cmd

	done

	global_trace=${oDir}/${SSS}_GLOBAL.txt
	wm_trace=${oDir}/${SSS}_WM.txt
	csf_trace=${oDir}/${SSS}_CSF.txt

	# x, y, z + 3 rotational movements = first 6 columns, derivatives second 6
	mvmt_regressors=${iDir}/${SSS}/Movement_Regressors.txt
	ln -s ${mvmt_regressors} ${oDir}/

	# relative movement
	relmvmt_regressors=${iDir}/${SSS}/Movement_RelativeRMS.txt
	ln -s ${relmvmt_regressors} ${oDir}/

	# # HCP cleaned time series 
	# hcpcleaned_algined_ts=${iDir}/${SSS}/${SSS}_Atlas_MSMAll_hp2000_clean.dtseries.nii
	# ln -s ${hcpcleaned_algined_ts} ${oDir}/

	# # time series MSM-ALL
	# aligned_ts=${iDir}/${SSS}/${SSS}_Atlas_MSMAll.dtseries.nii
	# ln -s ${aligned_ts} ${oDir}/

	############################################################################
	# now make a csv of what we need

	mov_top_col="trans_x,trans_y,trans_z,rot_x,rot_y,rot_z"
	echo $mov_top_col > ${oDir}//tmp_mov_regressors.csv

	cat ${mvmt_regressors} | \
		awk '{print $1,$2,$3,$4,$5,$6}' | \
		awk '{$1=$1}1' OFS=',' >> ${oDir}//tmp_mov_regressors.csv
	echo 'framewise_displacement' | cat - ${relmvmt_regressors} > ${oDir}/temp && mv ${oDir}/temp ${oDir}/tmp_fd.csv

	echo 'csf' | cat - ${csf_trace} > ${oDir}/temp && mv ${oDir}/temp ${oDir}/tmp_csf.csv
	echo 'white_matter' | cat - ${wm_trace} > ${oDir}/temp && mv ${oDir}/temp ${oDir}/tmp_wm.csv
	echo 'global_signal' | cat - ${global_trace} > ${oDir}/temp && mv ${oDir}/temp ${oDir}/tmp_global.csv

	paste -d , ${oDir}/tmp_mov_regressors.csv ${oDir}/tmp_fd.csv > \
		${oDir}/temp && mv ${oDir}/temp ${oDir}//${subj}_${SSS}_confounds.csv
	
	for iii in csf wm global ; do
		paste -d , ${oDir}/${subj}_${SSS}_confounds.csv ${oDir}/tmp_${iii}.csv > \
			${oDir}/temp && mv ${oDir}/temp ${oDir}/${subj}_${SSS}_confounds.csv
	done

	# remove spaces
	cat ${oDir}/${subj}_${SSS}_confounds.csv | sed 's,[[:blank:]],,g' > \
			${oDir}/temp && mv ${oDir}/temp ${oDir}/${subj}_${SSS}_confounds.csv

	# make a tsv
	cat ${oDir}/${subj}_${SSS}_confounds.csv | tr ',' '\t' > \
		${oDir}/${subj}_${SSS}_confounds.tsv

	ls ${oDir}/tmp_* && rm ${oDir}/tmp_*

	############################################################################
	############################################################################

	EXEDIR=/N/slate/jfaskowi/git_pull/app-fmri-2-mat_0p1p6/

	for XXX in WM CSF
	do
		if [[ ! -e ${oDir}/${subj}_${SSS}_${XXX}_acompcor.tsv ]] ; then
			counter=0
			looper="true"
			# put a loop in here
			while [[ ${looper} = "true" ]] && [[ ${counter} -lt 10 ]] ; do

				roimask=${XXX}_ROI

				cmd="${pybin} ${EXEDIR}/src/get_compcor.py \
						${oDir}/${SSS}_${XXX}_func.nii.gz \
						-mask ${!roimask} \
						-out ${oDir}/${XXX}_ \
						-prcnt 5 \
						-compcorstr ${XXX} \

					"
				echo $cmd #state the command
				log $cmd >> $OUT
				eval $cmd #execute the command

				# check if the output is no-zero
				if [[ -s ${oDir}/${XXX}_acompcor.csv ]] ; then
					looper="false"
					# make a tsv
					cat ${oDir}/${XXX}_acompcor.csv | tr ',' '\t' > \
						${oDir}/${subj}_${SSS}_${XXX}_acompcor.tsv && \
						rm ${oDir}/${XXX}_acompcor.csv 
				else
					echo "MADE AN EMPTY FILE. tyring again"
					counter=$((++counter))
				fi

			done # while loopers
		fi
	done # for XXX in WM CSF

	ls ${iDir}/${SSS}/${SSS}.nii.gz && rm ${iDir}/${SSS}/${SSS}.nii.gz
	ls ${workingDir}/*/*func.nii.gz && rm ${workingDir}/*/*func.nii.gz

done


done # BIG LOOP

end=`date +%s`
runtime=$((end-start))
echo "runtime: $runtime" 
log "runtime: $runtime" >> $
