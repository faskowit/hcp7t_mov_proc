#!/bin/bash

# setup my stuffs
source $HOME/myfunctions.sh
source $HOME/log.sh

module load python
module load afni
export AFNI_DONT_LOGFILE='YES'

module unload python
module load fsl

GETCONF=/N/slate/jfaskowi/git_pull/get_conf_4_regress/src/get_conf_frm_fmrip.py

####################################################################
####################################################################

#184
SUBJECT=($(cat /N/project/HCPaging/josh_sandbox/hcp7t/download/subjects.txt))
if [[ -z ${CMDLINE_IND} ]] ; then
	subj=${SUBJECT[${SLURM_ARRAY_TASK_ID:-$1}-1]}
else
	subj=${SUBJECT[${CMDLINE_IND}-1]}
fi
[[ -z ${subj} ]] && { echo "subj variable empty" ; exit 1 ; }

workingDir=/N/scratch/jfaskowi/hcp/func7t/nusregts_FIX2phys_noLP/${subj}/
mkdir -p $workingDir

scans_7T_MOVIE="tfMRI_MOVIE1_7T_AP tfMRI_MOVIE2_7T_PA tfMRI_MOVIE3_7T_PA tfMRI_MOVIE4_7T_AP"
scans_7T_REST="rfMRI_REST1_7T_PA rfMRI_REST2_7T_AP rfMRI_REST3_7T_PA rfMRI_REST4_7T_AP"

####################################################################
####################################################################
# setup stuff

CENSOR_THR=0.3472

# SET FILT in loop!!!
STRATEGY="-strategy 2phys -spikethr ${CENSOR_THR} "
FILT="0.008 0.50"

parcList1="BNatlas hcp-mmp-b schaefer200-yeo17 schaefer400-yeo17"
parcList2="suit_tianS2 suit_tianS3"
parcList3="kong200 kong400 kong800"
parcList4="yan200 yan400 yan800"

parcDir1=/N/slate/jfaskowi/data/fsLR32k_parcs/USE_DLABELS/
parcDir2=/N/slate/jfaskowi/data/fsLR32k_parcs/USE_SUBC_CERE_ALT/
parcDir3=/N/scratch/jfaskowi/hcp/parc/kong/
parcDir4=/N/slate/jfaskowi/git_pull/CBIG/stable_projects/brain_parcellation/Yan2023_homotopic/parcellations/HCP/fsLR32k/yeo17/

#go into the folder where the script should be run
cd $workingDir
echo "CHANGING DIRECTORY into $workingDir"

OUT=notes.txt
touch $OUT
PRINT_LOG_HEADER_DUDE $OUT

start=`date +%s`

WBCOMMAND=/N/slate/jfaskowi/software/workbench/bin_rh_linux64/wb_command 

for TTT in 7T_MOVIE 7T_REST ; do

#############################################################################
# first unzip ish

iZipDir=/N/project/HCPaging/josh_sandbox/hcp7t/download/

# unzip -n ${zipFile} -d ${workingDir}/ '*MSMAll*'

iDir=${workingDir}/${subj}/MNINonLinear/Results/

loopover="scans_${TTT}" 
for scan in ${!loopover} ; do

	echo "WORING ON SCAN: $scan"
	echo
	echo

	# zipFile=${iZipDir}/${subj}_${TTT}_2mm_fix.zip
	# unzip -n ${zipFile} -d ${workingDir}/ '*'${scan}'_Atlas_MSMAll_hp2000_clean.dtseries.nii'

	zipFile=${iZipDir}/${subj}_${TTT}_2mm_fix.zip
	unzip -n ${zipFile} -d ${workingDir}/ '*'${scan}'_Atlas_MSMAll_hp2000_clean.dtseries.nii'

	iDir=${workingDir}/${subj}/MNINonLinear/Results/${scan}/
	oDir=${workingDir}/${scan}/
	rDir=/N/scratch/jfaskowi/hcp/func7t/regressors/${subj}/${scan}/
	mkdir -p ${oDir}

	inputCifti=${iDir}/${scan}_Atlas_MSMAll_hp2000_clean.dtseries.nii

	inputConf=${rDir}/${subj}_${scan}_confounds.tsv

	if [[ ! -e ${inputCifti} ]] ; then
		echo "noooo $inputCifti"
		touch ${oDir}/noCifti.yo
		continue
	fi

	# check if the output for the last atlas has been made
	lastparc=$(echo $parcList4 | fmt -1 | sort | tail -1)
	if [[ -e ${oDir}/${lastparc}.ptseries.nii.gz ]] ; then
		echo $lastparc
		echo "timeseries already made"
		continue
	fi

	# lastparc=$(echo $parcList2 | fmt -1 | sort | tail -1)
	# lpkong=$(echo $parcList3 | fmt -1 | sort | tail -1)
	# lp3=${parcDir3}/${lpkong/kong/}/${subj}_kong22_17nets_sz${lpkong/kong/}.dlabel.nii
	# if [[ -e ${oDir}/${lastparc}.ptseries.nii.gz ]] && \
	# 		[[ ! -e ${lp3} ]]; then
	# 	echo $lastparc
	# 	echo "timeseries already made and the kong does not exist"
	# 	continue
	# fi

	# need to add compcor files to regressors file
	# ccDir=/N/dc2/scratch/jfaskowi/proj/hcp1200/func/regressors//${subj}/${scan}/
	ccWM=${rDir}/${subj}_${scan}_WM_acompcor.tsv
	ccCSF=${rDir}/${subj}_${scan}_CSF_acompcor.tsv

	inputConf=${rDir}/${subj}_${scan}_confounds.tsv
	inputTaskReg=${rDir}/${scan}_convTaskReg.tsv

	# check if conv generally exists
	if [[ ! -e ${inputConf} ]] ; then
		echo "no confounds"
		continue
	fi

	paste ${ccWM} ${ccCSF} > ${oDir}/acompcor_combo.tsv
	paste ${inputConf} ${oDir}/acompcor_combo.tsv > ${oDir}/all_regressors.tsv

	############################################################################
	# first convert from cifti to wb command

	cmd="${WBCOMMAND} \
			-cifti-convert -to-nifti \
			${inputCifti} ${oDir}/tmp.nii.gz \
		"
	echo $cmd #state the command
	log $cmd >> $OUT
	[[ ! -e ${oDir}/tmp.nii.gz ]] && eval $cmd

	inTR=$( ${WBCOMMAND} -file-information -only-step-interval ${inputCifti} )
	discardVols=0

	############################################################################
	# also get the mean 

	cmd="${WBCOMMAND} \
			-cifti-reduce \
			${inputCifti} \
			MEAN \
			${oDir}/mean.dscalar.nii \
			-only-numeric \
		"
	echo $cmd #state the command
	log $cmd >> $OUT
	eval $cmd #execute the command

	############################################################################
	# regress it

	cmd="$py_bin ${GETCONF} \
			${oDir}/all_regressors.tsv \
			-out ${oDir}/out \
			-cen \
			${STRATEGY} \
		"
	echo $cmd 
	log $cmd >> $OUT
	eval $cmd #execute the command

	# sucessful regression with the python tool... we will have this file:
	outDF=${oDir}/out_conf.csv
	mv ${oDir}/out_cen.csv ${oDir}/out_cen.txt
	outCen=${oDir}/out_cen.txt

	mkdir -p ${oDir}/out_reg/

	cmd="3dTproject \
			-input ${oDir}/tmp.nii.gz
			-prefix ${oDir}/out_reg/out.nii.gz \
			-ort ${outDF} \
			-polort 2 \
			-TR ${inTR} \
			-passband ${FILT} \
			-censor ${outCen} \
			-cenmode NTRP \
		"
	echo $cmd #state the command
	log $cmd >> $OUT
	eval $cmd #execute the command

	# check if sucessfull?
	if [[ ! -e ${oDir}/out_reg/out.nii.gz ]] ; then
		echo "too many regressors... did not work"
		ls ${inputCifti} && rm ${inputCifti}
		ls ${oDir}/tmp.nii.gz && rm ${oDir}/tmp.nii.gz
		continue 
	fi

	############################################################################
	# convert back to cifti

	cmd="${WBCOMMAND} \
			-cifti-convert -from-nifti \
			${oDir}/out_reg/out.nii.gz \
			${inputCifti} \
			${oDir}/out_reg/out_nuisance_cifti.dtseries.nii \
			-reset-timepoints ${inTR} ${discardVols} \

		"
	echo $cmd #state the command
	log $cmd >> $OUT
	eval $cmd #execute the command

	# add in the mean
	cmd="${WBCOMMAND} \
			-cifti-math \
			'x + y' \
			${oDir}/out_reg/out_nuisance_cifti_wMean.dtseries.nii \
			-var x ${oDir}/out_reg/out_nuisance_cifti.dtseries.nii \
			-var y ${oDir}/mean.dscalar.nii \
			-select 1 1 -repeat \
		"
	echo $cmd #state the command
	log $cmd >> $OUT
	eval $cmd #execute the command

	#######################################################################

	rm ${oDir}/out_reg/out.nii.gz
	rm ${oDir}/tmp.nii.gz
	rm ${oDir}/*tsv
	rm ${oDir}/out_reg/out_nuisance_cifti.dtseries.nii 
	rm ${oDir}/mean.dscalar.nii

	ls ${inputCifti} && rm ${inputCifti}

	regressCIFTI=${oDir}/out_reg/out_nuisance_cifti_wMean.dtseries.nii
	if [[ -e ${regressCIFTI} ]] ; then
		echo "good to go"
	else
		echo "ERROR"
		continue
	fi

	#######################################################################
	# parcellate

	# GROUP AVERAGE PARCS
	for ppp in ${parcList1} ; do

		currParc=${parcDir1}/${ppp}_volstruct.dlabel.nii

		cmd="${WBCOMMAND} \
				-cifti-parcellate \
				${regressCIFTI} \
				${currParc} \
				COLUMN \
				${oDir}/${ppp}.ptseries.nii \
				-method MEAN \
				-legacy-mode \
			"
	    echo $cmd #state the command
	    log $cmd >> $OUT
	    eval $cmd #execute the command

	    # and gzip 
	    gzip ${oDir}/${ppp}.ptseries.nii

	done

	# SUIT TIAN
	for ppp in ${parcList2} ; do

		currParc=${parcDir2}/${ppp}.cifti.dlabel.nii

		cmd="${WBCOMMAND} \
				-cifti-parcellate \
				${regressCIFTI} \
				${currParc} \
				COLUMN \
				${oDir}/${ppp}.ptseries.nii \
				-method MEAN \
				-legacy-mode \
			"
	    echo $cmd #state the command
	    log $cmd >> $OUT
	    eval $cmd #execute the command

	    # and gzip 
	    gzip ${oDir}/${ppp}.ptseries.nii

	done

	# KONG INDIVIDUALIZED PARCS
	for ppp in ${parcList3} ; do

		currParc=${parcDir3}/${ppp/kong/}/${subj}_kong22_17nets_sz${ppp/kong/}.dlabel.nii

		if [[ -e $currParc ]] ; then

			cmd="${WBCOMMAND} \
					-cifti-parcellate \
					${regressCIFTI} \
					${currParc} \
					COLUMN \
					${oDir}/${ppp}.ptseries.nii \
					-method MEAN \
					-legacy-mode \
				"
		    echo $cmd #state the command
		    log $cmd >> $OUT
		    eval $cmd #execute the command

		    # and gzip 
		    gzip ${oDir}/${ppp}.ptseries.nii

		fi

	done

	# Yan homotopic
	for ppp in ${parcList4} ; do

		currParc=${parcDir4}/${ppp/yan/}Parcels_Yeo2011_17Networks.dlabel.nii

		if [[ -e $currParc ]] ; then

			cmd="${WBCOMMAND} \
					-cifti-parcellate \
					${regressCIFTI} \
					${currParc} \
					COLUMN \
					${oDir}/${ppp}.ptseries.nii \
					-method MEAN \
					-legacy-mode \
				"
		    echo $cmd #state the command
		    log $cmd >> $OUT
		    eval $cmd #execute the command

		    # and gzip 
		    gzip ${oDir}/${ppp}.ptseries.nii

		fi

	done

	# # and now gzip
	# gzip ${regressCIFTI}
	ls ${regressCIFTI} && rm ${regressCIFTI}

done

done # end big loop

end=`date +%s`
runtime=$((end-start))
echo "runtime: $runtime"
log "runtime: $runtime" >> $OUT
