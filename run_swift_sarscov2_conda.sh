#!/bin/bash
# set -eu
# set -x

# Swift NGS analysis workflow for SARS-CoV-2 amplicon panel
# S. Sandhu, S. Chaluvadi and J. Irish 20200809
# CHANGELOG:
# 200809 - this script has been updated to run on the machine hosting Docker,
#          and tools in separate docker images built with docker-compose

export DISPLAY=:1.0
checkprimerOT="0"
downsample="0"
singleEndReads="0"
metrics="1" # run metrics-only in absence of -v option

mincov="100" # minimum coverage for calling a base in consensus (N-masked if below $mincov)
ploidy="2" # test ploidy option in HaplotypeCaller

# Print usage function along command line arguments
usage()
{
cat<<EOF
Usage: $0 [OPTIONS] masterfile.txt
OPTIONS:
 -h Show usage
 -v Run variant calling workflow (includes metrics)
 -o Run checks for primer counts in off-target alignments
 -d Run checks for primer counts in off-target alignments
 -s Run Single-End reads (one Fastq file per library)
 -a Print all tool versions for Swift NGS analysis SARS-CoV-2
EOF
}

# If no argumenents are supplied by user run usage function
if [ "$#" -eq 0 ]
then
    usage
    exit 1
fi

while getopts ":mvodspa" opt; do
    case "${opt}" in
    h)
      usage
      exit 1
      ;;
    v)
      metrics="0"
      echo "Running variant calling workflow (includes metrics)"
      ;;
    o)
      checkprimerOT="1" # 190107
      echo "running checks for primer counts in off-target alignments"
      ;;
    d)
      downsample="1" # 190107
      echo "running checks for primer counts in off-target alignments"
      ;;
    s)
      singleEndReads="1" # 200520
      echo "Single-End reads (one Fastq file per library)"
      ;;
    a)
 #     printversions="1"
#      echo "Print all Tool versions for Swift NGS analysis SARS-CoV-2"
      ;;
    \?)
      usage
      exit
      ;;
    esac
done

shift $((OPTIND-1))

shopt -s expand_aliases



# args specified on command line when calling script:
coremaster="$1"
maxreads="${2:-20000000}"
ref="/data/swift_sarscov2_ref_genomes/covid19.fasta"
#hybridref="/data/swift_sarscov2_ref_genomes/sarscov2_homosapiens_assembly19broad_hybrid.fasta"
hg37ref="/data/swift_sarscov2_ref_genomes/Homo_sapiens_assembly19broad.fasta"

# start organization
rundirnameroot="$(echo "${coremaster}" | tr '_' '\t' | awk '{print $1}')"
runstart="$(date +%y%m%d_%H.%M.%S)"
rundir="${rundirnameroot}"_"${runstart}"

mkdir -p "${rundir}"
cd "${rundir}"
cp /data/*.fastq.gz .
cp /data/"${coremaster}" .


# start organization
mkdir -p tmp fastq fastqc bed bam metrics logs plots pangolin

# common paths and script-specific aliases
# ref=/rseq/rgenomes/Homo_sapiens_assembly19broad.fasta
#anno=/tools/snpEff

######*** code to generate BED files from master files ./***######
echo "Creating BED files from masterfile"

# non-merged target BED from coremaster
awk '{print $1,$2,$3,$4}' OFS="\t" "${coremaster}" | \
    sort -k1,1n -k2,2n > core_nonmerged_targets.bed

# merged target BED for core
bedtools merge -c 4 -o distinct -delim ";" \
    -i core_nonmerged_targets.bed | \
    sed 's/;.*//' | \
    sort -k1,1n -k2,2n > core_merged_targets.bed

### overlap-removed non-merged target BED ###
# get all overlapping regions for target bedfile
# NOTE: awk step isolates overlapping regions and removes full regions
#       (intersectBed outputs all full regions as they self-intersect)
bedtools intersect \
    -a core_nonmerged_targets.bed -b core_nonmerged_targets.bed |
    awk 'a[$1FS$2FS$3]++' OFS="\t" | tr -d '\r' > core_overlapped_regions.bed

# 180719 handle edge case where core_overlapped_regions.bed is empty
if [ ! -s core_overlapped_regions.bed ]
then
    echo "No overlapping amplicons found in non-merged target BED."
    cp core_nonmerged_targets.bed core_nonmerged_noolaps_targets.bed
else
    bedtools subtract \
        -a core_nonmerged_targets.bed -b core_overlapped_regions.bed |
        tr -d '\r' > core_nonmerged_noolaps_targets.bed
fi

mv core_overlapped_regions.bed bed

# primer BED (for primer trimming)
awk '{print $1,$5,$6,$7;print $1,$8,$9,$10}' OFS="\t" "${coremaster}" \
    > core_primers.bed

# 200322 full amplicon regions BED
awk '{print $1,$5,$9,$4}' OFS="\t" "${coremaster}" \
    > core_amplicons_nonmerged.bed

bedtools merge -c 4 -o distinct -delim ";" -i core_amplicons_nonmerged.bed | \
    sed 's/;.*//' > core_amplicons_merged.bed

awk '{print $1,$2,$3,"+",$4}' OFS="\t" core_amplicons_merged.bed \
    > core_amplicons_merged_5col.bed

# Convert target BED files to 5-column format for analysis workflow
for f in core*targets.bed
do
    awk '{print $1,$2,$3,"+",$4}' OFS="\t" "$f" > "${f%%.bed}_5col.bed"
done

# variables to make changes easier
bedfile=core_merged_targets_5col.bed
nomergebed=core_nonmerged_targets_5col.bed
olapfreebed=core_nonmerged_noolaps_targets_5col.bed
ampbed=core_amplicons_merged_5col.bed

mv ./*targets.bed bed

# 200310
cp "${coremaster}" totalmaster.tmp

awk '{print $1,$2,$3,$4}' OFS="\t" "${coremaster}" |
    sort -k1,1n -k2,2n > total_nonmerged_targets.bed

bedtools merge -c 4 -o distinct -delim ";" -i total_nonmerged_targets.bed |
    sed 's/;.*//' |
    sort -k1,1n -k2,2n > total_merged_targets.bed

awk '{print $1,$5,$6,$7;print $1,$8,$9,$10}' OFS="\t" "${coremaster}" \
    > total_primers.bed

#totalmergedbed=total_merged_targets.bed
#totalprimers=total_primers.bed

###############################################################################
###### begin workflow for each pair of fastq files in working directory #######
###############################################################################

for f in *_R1_001.fastq.gz
do
    # SE Reads
    if [ "$singleEndReads" = "1" ]
    then
        fq1="$f"
        # fq2="${fq1%%_R1_*}"_R2_001.fastq.gz
        prefix="${fq1%%_R1_001.fastq.gz}"

        echo "$prefix"

        ### run FASTQC ###
        echo "running fastqc"
        fastqc -t 8 "$fq1"
        mv ./*fastqc.zip fastqc

        # TODO: clean up requirement for this empty file
        echo "0" > "${prefix}"_R2_001_fastqc_NNNNN.tmp

        # TODO: clean up requirement for this empty file
        paste "${prefix}"_R1_001_fastqc_NNNNN.tmp "${prefix}"_R2_001_fastqc_NNNNN.tmp \
            > "${prefix}"_pctNNNNN.txt

        # TODO: clean up requirement for this empty file
        mv "${prefix}"_R1_001_fastqc_NNNNN.tmp fastqc
        mv "${prefix}"_R2_001_fastqc_NNNNN.tmp fastqc

        ### trim adapters ###
        # Illumina adapter trimming setup (Trimmomatic)
        # trimdir=/tools/trimmomatic36

        echo "Trimming Illumina adapters"
        # NOTE: custom adapter file for Accel-amplicon Illumina adapter trimming
        trimmomatic  SE \
            -threads 6 -trimlog "${prefix}"_trimmatic_trimlog.log \
            "$fq1" "${prefix}"_R1_atrimd.fq.gz \
            ILLUMINACLIP:/usr/local/src/trimmomatic/TruSeq3-SE.fa:2:30:10 \
            #ILLUMINACLIP:/adapters/TruSeq3-SE.fa:2:30:10 \
            MINLEN:30 2> "${prefix}"_01_atrim.log
            # ILLUMINACLIP:"${trimdir}"/adapters/TruSeq3-SE.fa:2:30:10 \

        rm ./*unpaired*.fq.gz
        fqt1="${prefix}"_R1_atrimd.fq.gz
        # fqt2="${prefix}"_R2_atrimd.fq.gz

        # 200509 downsample after adapter trimming and read filtering
        if [ "$downsample" = "1" ]
        then
            echo "Downsampling to total of ${maxreads} reads" >&2
            lncnt=$(echo $maxreads | awk '{print $1*2}')
            zcat $fqt1 | head -n $lncnt | gzip > "${prefix}"_R1_atrimd_dnsmpl.fq.gz
            # zcat $fqt2 | head -n $lncnt | gzip > "${prefix}"_R1_atrimd_dnsmpl.fq.gz
            fqt1="${prefix}"_R1_atrimd_dnsmpl.fq.gz
            # fqt2="${prefix}"_R1_atrimd_dnsmpl.fq.gz
        fi

        ### align reads ###
        echo "Aligning with bwa b37"
        bwa mem "$ref" "$fqt1" -U 17 -M -t 12 \
            -o "${prefix}"_nontrimd.sam \
            2> "${prefix}"_02_bwa.log

        samtools view -Sc "${prefix}"_nontrimd.sam \
            > "${prefix}"_nontrimd_readct.log

        ### name-sort alignment file
        echo "Name-sorting SAM file for primerclip"
        samtools sort -@ 12 -n -O SAM "${prefix}"_nontrimd.sam \
            > "${prefix}"_nontrimd_namesrtd.sam \
            2> "${prefix}"_02_2_namesort.log

        ### trim primers ###
        echo "Trimming primers"
        primerclip -s "${coremaster}" "${prefix}"_nontrimd_namesrtd.sam "${prefix}"_ptrimd.sam 2> "${prefix}"_03_ptrim.log
    else
        # PE Reads
        fq1="$f"
        fq2="${fq1%%_R1_*}"_R2_001.fastq.gz
        prefix="${fq1%%_R1_001.fastq.gz}"

        echo "$prefix"

        ### run FASTQC ###
        echo "running fastqc"
        fastqc -t 8 "$fq1" "$fq2"
        mv ./*fastqc.* fastqc

        echo "0" > "${prefix}"_R1_001_fastqc_NNNNN.tmp
        echo "0" > "${prefix}"_R2_001_fastqc_NNNNN.tmp

        paste "${prefix}"_R1_001_fastqc_NNNNN.tmp "${prefix}"_R2_001_fastqc_NNNNN.tmp \
            > "${prefix}"_pctNNNNN.txt

        mv "${prefix}"_R1_001_fastqc_NNNNN.tmp fastqc
        mv "${prefix}"_R2_001_fastqc_NNNNN.tmp fastqc

        ### trim adapters ###
        # Illumina adapter trimming setup (Trimmomatic)
        # trimdir=/tools/trimmomatic36

        echo "Trimming Illumina adapters"
        # NOTE: custom adapter file for Accel-amplicon Illumina adapter trimming
        # 200521 remove minlen:30 filter to allow short read (dimer) counting
        # 200805 two-step ILLUMINACLIP testing to better remove adapter and downstream dark bases from short reads
        trimmomatic PE \
            -threads 6 -trimlog "${prefix}"_trimmomatic_trimlog.log \
            "$fq1" "$fq2" \
            "${prefix}"_R1_atrimd_nominlen.fq.gz \
            "${prefix}"_unpaired_R1_nominlen.fq.gz \
            "${prefix}"_R2_atrimd_nominlen.fq.gz \
            "${prefix}"_unpaired_R2_nominlen.fq.gz \
            ILLUMINACLIP:/usr/local/src/trimmomatic/TruSeq3-PE-JI.fa:2:30:10:1:true \
            ILLUMINACLIP:/usr/local/src/trimmomatic/TruSeq3-PE-JI2.fa:2:30:10 \
            2> "${prefix}"_01_atrim_nominlen.log

        cat <(zcat "${prefix}"_R1_atrimd_nominlen.fq.gz | paste - - - - |
              awk '{print $3}') \
            <(zcat "${prefix}"_R2_atrimd_nominlen.fq.gz | paste - - - - |
              awk '{print $3}') |
              awk -v prefix="$prefix" \
                  'BEGIN{n=0}{if(length($1) <= 100){n++}}END{print "sample","dimer_reads","total_reads","%dimers"; print prefix,n,NR,(n/NR*100.0)}' \
                OFS="\t" > "${prefix}"_dimer_report.txt

        trimmomatic PE \
            -threads 6 -trimlog "${prefix}"_trimmomatic_trimlog_minlen.log \
            "${prefix}"_R1_atrimd_nominlen.fq.gz \
            "${prefix}"_R2_atrimd_nominlen.fq.gz \
            "${prefix}"_R1_atrimd.fq.gz \
            "${prefix}"_unpaired_R1.fq.gz \
            "${prefix}"_R2_atrimd.fq.gz \
            "${prefix}"_unpaired_R2.fq.gz \
            SLIDINGWINDOW:10:28 \
            MINLEN:30 \
            2> "${prefix}"_01_atrim.log

        rm ./*unpaired*.fq.gz
        rm ./*nominlen*.fq.gz

        fqt1="${prefix}"_R1_atrimd.fq.gz
        fqt2="${prefix}"_R2_atrimd.fq.gz

        # 200509 downsample after adapter trimming and read filtering
        if [ "$downsample" = "1" ]
        then
            echo "Downsampling to total of ${maxreads} reads" >&2
            # lncnt=$(echo $maxreads | awk '{print $1*2}')
            # zcat $fqt1 | head -n $lncnt | gzip > "${prefix}"_R1_atrimd_dnsmpl.fq.gz
            # zcat $fqt2 | head -n $lncnt | gzip > "${prefix}"_R2_atrimd_dnsmpl.fq.gz
            # 200709 use seqtk to randomly sample fastq files for downsampling
            numrds=$(echo $maxreads | awk '{printf("%.0f", $1/2.0)}')
            seqtk sample -s seed=11 "${fqt1}" "${numrds}" |
                gzip > "${prefix}"_R1_atrimd_dnsmpl.fq.gz
            seqtk sample -s seed=11 "${fqt2}" "${numrds}" |
                gzip > "${prefix}"_R2_atrimd_dnsmpl.fq.gz
            fqt1="${prefix}"_R1_atrimd_dnsmpl.fq.gz
            fqt2="${prefix}"_R2_atrimd_dnsmpl.fq.gz
        fi

        ### align reads ###
        echo "Aligning with bwa to sarscov2 reference"
        bwa mem "$ref" "$fqt1" "$fqt2" -U 17 -M -t 12 \
            -o "${prefix}"_nontrimd.sam \
            2> "${prefix}"_02_bwa.log

        # 200.05
        echo "Aligning non-SARS2_aligned reads to hg37"
        samtools view -h -f 4 -O BAM "${prefix}"_nontrimd.sam \
            -o "${prefix}"_nontrimd_sars2nomap.bam \
            2> "${prefix}"_s2nomap_sam2bam.log

        picard SamToFastq \
            -I "${prefix}"_nontrimd_sars2nomap.bam \
            -F "${prefix}"_sars2nomap_R1_001.fastq \
            -F2 "${prefix}"_sars2nomap_R2_001.fastq \
            -UNPAIRED_FASTQ "${prefix}"_sars2nomap_unpaired.fastq \
            -VALIDATION_STRINGENCY LENIENT \
            2> "${prefix}"_sam2fq.log

        bwa mem "$hg37ref" "${prefix}"_sars2nomap_R1_001.fastq \
            "${prefix}"_sars2nomap_R2_001.fastq \
            -U 17 -M -t 12 -o "${prefix}"_s2nomap_hg37.sam \
            2> "${prefix}"_02_s2nomaphg37.log

        samtools view -h -O BAM "${prefix}"_s2nomap_hg37.sam \
            -o "${prefix}"_s2nomap_hg37.bam

        samtools sort "${prefix}"_s2nomap_hg37.bam \
            -o "${prefix}"_s2nomap_hg37srt.bam

        samtools index "${prefix}"_s2nomap_hg37srt.bam

        picard CollectAlignmentSummaryMetrics \
            -R "$hg37ref" -I "${prefix}"_s2nomap_hg37srt.bam \
            -O "${prefix}"_s2nomap_hg37_alnmetrics.txt \
            2> "${prefix}"_alnsummmetrics.log

        samtools view -Sc "${prefix}"_nontrimd.sam \
            -o "${prefix}"_nontrimd_readct.log

        # 200810
        rm ./*.fastq

        ### name-sort alignment file
        echo "Name-sorting SAM file for primerclip"
        samtools sort -@ 12 -n -O SAM "${prefix}"_nontrimd.sam \
            -o "${prefix}"_nontrimd_namesrtd.sam \
            2> "${prefix}"_02_2_namesort.log

        ### trim primers ###
        echo "Trimming primers"
        primerclip "${coremaster}" \
            "${prefix}"_nontrimd_namesrtd.sam \
            "${prefix}"_ptrimd.sam 2> "${prefix}"_03_ptrim.log

    fi

    echo "sorting and adding read groups"
    picard AddOrReplaceReadGroups \
        -I "${prefix}"_ptrimd.sam -O "${prefix}"_sarscov2.bam \
        -SO coordinate -RGID snpID -LB swift -SM "${prefix}" -PL illumina -PU miseq \
        -VALIDATION_STRINGENCY LENIENT \
        2> "${prefix}"_04_addRGs.log

    # save non-primertrimd BAM file for debugging and inspection
    #$picard SortSam I=${prefix}_nontrimd.sam O=${prefix}_nontrimd.bam \
    #    CREATE_INDEX=true SORT_ORDER=coordinate \
    #    VALIDATION_STRINGENCY=LENIENT 2> ${prefix}_05_makenonptrimdbam.log
    picard AddOrReplaceReadGroups \
        -I "${prefix}"_nontrimd.sam -O "${prefix}"_nontrimd.bam \
        -SO coordinate -RGID snpID -LB swift -SM "${prefix}" -PL illumina -PU miseq \
        -VALIDATION_STRINGENCY LENIENT \
        2> "${prefix}"_05_makenonptrimdbam.log

    samtools index "${prefix}"_nontrimd.bam \
        2> "${prefix}"_05_makenonptrimdbam_index.log

    echo "indexing bam file"
    samtools index "${prefix}"_sarscov2.bam \
        2> "${prefix}"_06_index.log

    ### calculate coverage metrics ###
    echo "calculating coverage metrics"
    bedtools coverage -b "${prefix}"_sarscov2.bam -a "${bedfile}" -d > "${prefix}".covd
    awk '{sum+=$7}END{m=(sum/NR); b=m*0.2; c=m*0.05; print m, b, c}' "${prefix}".covd > "${prefix}"_covd.tmp 2> "${prefix}"_06_cov1.log

    # make an amplicon-specific coverage metrics report
    # NOTE: coverage is not uniquely assigned to individual amplicons
    #       for overlapping regions!
    # UPDATE 190520 remove -d option to get amplicon coverage as sum of alns
    # covering any part of amplicon target region (per amplicon)
    bedtools coverage -b "${prefix}"_sarscov2.bam -a "${nomergebed}" |
        sort -k1,1n -k2,2n \
        > "${prefix}"_amplicon_coverage.cov 2> "${prefix}"_07_cov2.log

    # 190520JCI
    awk '{sum+=$6}END{m=(sum/NR); b=m*0.2; print m, b}' OFS="\t" \
        "${prefix}"_amplicon_coverage.cov \
        > "${prefix}"_cov.tmp 2> "${prefix}"_06_cov1_1.log

    # make an amplicon-specific coverage metrics report with olaps omitted
    # and report mean amplicon coverage using bedtool option (170228 JCI)
    bedtools coverage -b "${prefix}"_sarscov2.bam \
        -a "${olapfreebed}" -d \
        > "${prefix}"_olapfree.covd 2> "${prefix}"_08_cov3.log

    awk 'BEGIN{n=0}NR==FNR{m=$1;b=$2;c=$3;next}{if($7>=b)n++}END{print m,b,c,(n/FNR*100.0)}' \
        OFS="\t" "${prefix}"_covd.tmp "${prefix}".covd \
        > "${prefix}"_covMetrics.txt

    awk 'BEGIN{n=0}NR==FNR{m=$1;b=$2;next}{if($6>=b)n++}END{print m,b,(n/FNR*100.0)}' \
        OFS="\t" "${prefix}"_covd.tmp "${prefix}"_amplicon_coverage.cov \
        > "${prefix}"_ampcovMetrics.txt

    echo "calculating mean amplicon coverage"
    # find mean amplicon coverage using coverage metrics for
    # non-overlapping regions of each amplicon
    # 20180818 add target start and end annotations to ampmeancov
    awk '{a[$5]+=$7;b[$5]=$6}END{for(i in a){print i, (a[i]/b[i])}}' \
        OFS="\t" <(sort -k6,6n "${prefix}"_olapfree.covd) |
        sort -k2,2g |
        awk 'NR==FNR{a[$4]=$2OFS$3;next}{$3=a[$1]}1' \
        OFS="\t" "${coremaster}" - | tr ' ' '\t' \
        > "${prefix}"_ampmeancov.covd

    # 200810 new plotcov (python script located at /usr/local/src/plotcov3)
    /usr/local/src/plotcov3/plotcov3 --meancov "${prefix}"_ampmeancov.covd \
              --nolapcov "${prefix}"_olapfree.covd \
              --covmetrics "${prefix}"_covMetrics.txt \
              --outprefix "${prefix}"

    rm ./*covd.tmp
    rm ./*.sam

    ### NOTE: 170410 should we use amplicon coords for _fullintervals? ###
    # make intervals file for CollectTargetedPcrMetrics
    samtools view -H "${prefix}"_sarscov2.bam \
        -o "${prefix}"_header.txt

    cat "${prefix}"_header.txt "${ampbed}" > "${prefix}"_fullintervals
    cat "${prefix}"_header.txt "${bedfile}" \
        > "${prefix}"_noprimerintervals

    # find on-target metrics using picard-tools
    echo "Running CollectTargetedPcrMetrics"
    picard CollectTargetedPcrMetrics \
        -I "${prefix}"_sarscov2.bam \
        -O "${prefix}"_targetPCRmetrics.txt -AI "${prefix}"_fullintervals \
        -TI "${prefix}"_noprimerintervals -R "$ref" \
        -PER_TARGET_COVERAGE "${prefix}"_perTargetCov.txt \
        -VALIDATION_STRINGENCY LENIENT \
        2> "${prefix}"_09_pcrmetrics.log

    # 200509 check metrics on non-trimmed bam for comparison
    echo "Running CollectTargetedPcrMetrics for non-trimmed sequences"
    picard CollectTargetedPcrMetrics \
        -I "${prefix}"_nontrimd.bam \
        -O "${prefix}"_targetPCRmetrics_noptrim.txt -AI "${prefix}"_fullintervals \
        -TI "${prefix}"_noprimerintervals -R "${ref}" \
        -PER_TARGET_COVERAGE "${prefix}"_perTargetCov_noptrim.txt \
        -VALIDATION_STRINGENCY LENIENT \
        2> "${prefix}"_09_pcrmetrics_noptrim.log

    # 190107 primer OT checking
    if [ "$checkprimerOT" = "1" ]
    then
        ###############################################################################
        ########################   check primers   ####################################
        ###############################################################################
        echo "Checking primers for off-target binding sites"
        /usr/local/pipelines/amplicon_OTchecker_200316.sh \
            "${coremaster}" "${prefix}" "$fqt1" "$fqt2"
        echo "Primer off-target check complete"
    fi

    if [ ! "$metrics" = "1" ]
    then
        ###############################################################################
        ########################  variant calling  ####################################
        ###############################################################################

        echo "Starting variant calling with GATK"
        # NOTE: gatk4
        gatk HaplotypeCaller -R "${ref}" \
            -I "${prefix}"_sarscov2.bam -L "${bedfile}" -O "${prefix}"_gatkHC.vcf \
            --dont-use-soft-clipped-bases -ploidy "${ploidy}"

        # Select variants with min-depth >= $mincov and allele-fraction >= 0.9
        gatk SelectVariants -R "${ref}" -V "${prefix}"_gatkHC.vcf \
            -select "vc.getGenotype(0).getAD().1 / vc.getGenotype(0).getDP() >= 0.9 && vc.getGenotype(0).getDP() >= ${mincov}" \
            -O "${prefix}"_filt.vcf
            #--java-options '-DGATK_STACKTRACE_ON_USER_EXCEPTION=true'

        echo "Calculating regions with coverage below ${mincov}X for N-masking consensus"
        bedtools genomecov -bga -ibam "${prefix}"_sarscov2.bam -g "${ref}" \
            > "${prefix}"_gencov.bdg \
            2> "${prefix}"_gencov.log

        awk -v mincv="${mincov}" '$4<mincv' OFS="\t" "${prefix}"_gencov.bdg \
            > "${prefix}"_ltmincov.bed \
            2> "${prefix}"_ltmincov.log

        # handle vcf files with zero calls by adding a fake call to avoid bcftools consensus error
        callcnt=$(grep '^[^#]' "${prefix}"_filt.vcf | wc -l)
        echo "Call count in filtered VCF: $callcnt"
        if [[ $callcnt -eq 0 ]]
        then
            > "${prefix}"_tmp.vcf
        else
            cp "${prefix}"_filt.vcf "${prefix}"_tmp.vcf
        # then
        #     cat "${prefix}"_filt.vcf \
        #         <(echo "NC_045512.2 25 FAKECALL T T 2000.00 . AC=1;AF=1.00;AN=1;DP=100;ExcessHet=0.0;FS=0.000;MLEAC=1;MLEAF=1.00;MQ=60.00;QD=30.00;SOR=2.000 GT:AD:DP:GQ:PL 0/0:100,100:100:99:0,1000" | tr ' ' '\t') \
        #     > "${prefix}"_tmp.vcf
        # else
        #     cp "${prefix}"_filt.vcf "${prefix}"_tmp.vcf
        fi
        bgzip "${prefix}"_gatkHC.vcf
        # bgzip "${prefix}"_tmp.vcf
        bcftools index "${prefix}"_gatkHC.vcf.gz
        bcftools consensus -m "${prefix}"_ltmincov.bed \
            -f $ref "${prefix}"_gatkHC.vcf.gz \
            > "${prefix}"_consensus.fa

        echo "Running nextclade on consensus FASTA"
        nextclade --input-fasta "${prefix}"_consensus.fa \
            --output-tsv "${prefix}"_nextclade_results.tsv

# F.C & Sandhu 210220
       echo "Running pangolin on consesnsus FASTA"
       pangolin "${prefix}"_consensus.fa --verbose --outdir pangolin/global_lineage_results --outfile "${prefix}"_pangolin_consensus.csv --panGUIlin 2> pangolin_verbose.log
       mv ./pangolin/global_lineage_results/global_lineage_information.csv ./pangolin/global_lineage_results/"${prefix}"_global_lineage_information.csv

       # echo "Running pangolin on consensus FASTA"
       # pangolin_d "/data/${prefix}_consensus.fa --panGUIlin --outdir /data/pangolin --outfile ${prefix}_pangolin_consensus.csv --verbose"
       # echo "Organizing global lineage file information!"
       # mv ./pangolin/global_lineage_information.csv ./pangolin/${prefix}_global_lineage_information.csv
       # rm -rf ./pangolin/logs
    fi
done

# Summarize on-target and coverage metrics for all samples into a single report
for f in ./*targetPCRmetrics.txt
do
    fname=$(basename $f)
    awk -v n="${fname%%_R1*}" 'NR==8{print n,$16,$20,$26*100.0,$41*100.0}' \
        OFS="\t" "$f" > "${f%%.txt}"_summary.txt
    f2="${f%%_target*}"_covMetrics.txt
    paste "${f%%.txt}"_summary.txt "$f2" > "${f2%%_cov*}"_combined_cov_metrics.txt
    # 195020JCI
    f3="${f%%_target*}"_ampcovMetrics.txt
    paste "${f%%.txt}"_summary.txt "$f3" > "${f3%%_ampcov*}"_combined_ampcov_metrics.txt
done

# 200824 summarize proportion of total reads aligned to sarscov2 vs. human
for f in ./*alnmetrics.txt
do
    fname=$(basename $f)
    sname=${fname%%_R1*}
    totreads=$(awk '{print $2}' "${f%%_s2nomap*}"_targetPCRmetrics_summary.txt)
    awk -v fnm="$sname" -v trds="$totreads" \
        'NR==10{print fnm,trds,$6,$6/trds*100.0}' OFS="\t" \
        "$f" \
        > "${fname%%.txt}"_summary.txt
done

for f in *_combined_cov_metrics.txt
do
    sed 's/_L00.*.txt//' $f >> final_metrics_report.tmp
done

cat *alnmetrics_summary.txt >> alnmetrics_summary.tmp

# 200811 create dimer report
[[ -f dimer_report.txt ]] && rm dimer_report.tmp

for f in *_dimer_report.txt
do
    awk 'NR==2{gsub(/_L00[1-9]/,"",$1); print $1,$2,$3,$4}' \
        OFS="\t" $f >> dimer_report.tmp
done

cat <(echo "sample dimer_reads total_reads %dimers") \
    dimer_report.tmp | tr ' ' '\t' > "${rundir}"_dimer_report.txt

# add dimer report to final_metrics_report
awk 'NR==FNR{a[$1]=$4;next}{$11=a[$1]}1' OFS="\t" \
    "${rundir}"_dimer_report.txt \
    final_metrics_report.tmp \
    > final_metrics_report.tmp2

awk 'NR==FNR{a[$1]=$4;next}{$12=a[$1]}1' OFS="\t" \
    alnmetrics_summary.tmp final_metrics_report.tmp2 \
    > final_metrics_report.tmp3

cat <(echo "Sample Total_Reads Reads_Aligned %Reads_Aligned Pct_10X_Cov" \
      "Mean_Coverage 20%Mean_Coverage 5%Mean_Coverage %Coverage_Uniformity" \
      "%Dimers %Human_Aligned" |
      tr ' ' '\t') \
    final_metrics_report.tmp3 |
    tr -s '\t' \
    > "${rundir}"_final_metrics_report.txt

# create excel file with final_metrics_report
/usr/local/src/report_to_excel_v3/report_to_excel_v3 --finmets "${rundir}"_final_metrics_report.txt
mv metrics_report.xlsx "${rundir}"_metrics_report.xlsx

# F.C & Sandhu 210225
echo "Summarizing lineage information from Pangolin"
echo -e "Sample\tlineage\tprobability\tpangoLEARN_version\tstatus\tnote\ttaxon" > pangoheader.txt
for f in pangolin/global_lineage_results/*_consensus.csv ; do sed 's/,/\t/g' $f | awk -v fname="${f%_R1*}" 'NR==2 {print fname, $2,$3,$4,$5,$6,$1}' > ${f%.csv}.tmp4; done
cat pangoheader.txt pangolin/global_lineage_results/*.tmp4 > pangolin_lineage.tmp

echo "Summarize global lineage PANGOLIN"
echo -e "LineageName\tMost_common_countries\tDate_Range\tNumberof_taxa\tDays_sinceLast_sampling" > panglobheader.txt
for f in ./pangolin/global_lineage_results/*_information.csv ; do sed 's/,/\t/g' $f | awk 'NR==2' > ${f%.csv}.tmp5; done
cat panglobheader.txt pangolin/global_lineage_results/*.tmp5 > pangolin_globalin.tmp
paste pangolin_lineage.tmp pangolin_globalin.tmp > pangolin_lineage_report.txt

echo "Summarizing Nextclade results"
for g in *.tsv
 do
     head -n1 $g > nextclad_header.txt
     awk -v fname="${g%_R1*}" 'NR==2 {print fname, $0}' $g > ${g%.tsv}.tmp5
done

cat nextclad_header.txt ./*.tmp5 > nextclade_Clade_report.txt

# Clean up tmp files and organize output

rm *.tmp
rm *.tmp[2-5]
rm *header.txt
rm *summary.txt
rm *intervals

mv ./*.log logs/
mv ./*.bed bed/
mv ./*.covd metrics/
mv ./*.cov metrics/
mv ./*metrics.txt metrics/
mv ./*perTargetCov.txt metrics/
mv ./*.fastq.gz fastq/
mv ./*.fq.gz fastq/
mv ./*nontrim* tmp/
mv ./*s2nomap* tmp/
mv ./*_report.txt metrics/
mv ./*.txt tmp/
mv ./*.p* plots/
mv ./*.ba* bam/

if [ ! "$metrics" = "1" ]
then
    mkdir -p vcf consensus nextclade
    mv ./*.vcf vcf
    mv ./*.idx vcf
    mv ./*.bdg metrics
    mv ./*.tsv nextclade
#    mv ./*.csv pangolin
    mv ./*consensus.fa consensus
    mv ./*.vcf.gz* vcf
    mv ./metrics/nextclade_Clade_report.txt ./
    mv ./metrics/pangolin_lineage_report.txt ./
fi

conda list --export > "${rundir}"_package_list.txt

echo "analysis workflow finished."
echo "Please check out the new plots (.pdf files) and the excel report file (metrics_report.xlsx)"
