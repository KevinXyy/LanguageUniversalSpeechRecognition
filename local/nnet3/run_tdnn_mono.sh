#!/usr/bin/env bash

#    This is the standard "tdnn" system, built in nnet3 with xconfigs.


# local/nnet3/compare_wer.sh exp/nnet3/tdnn1a_sp
# System                tdnn1a_sp
#WER dev93 (tgpr)                9.18
#WER dev93 (tg)                  8.59
#WER dev93 (big-dict,tgpr)       6.45
#WER dev93 (big-dict,fg)         5.83
#WER eval92 (tgpr)               6.15
#WER eval92 (tg)                 5.55
#WER eval92 (big-dict,tgpr)      3.58
#WER eval92 (big-dict,fg)        2.98
# Final train prob        -0.7200
# Final valid prob        -0.8834
# Final train acc          0.7762
# Final valid acc          0.7301

set -e -o pipefail -u

# First the options that are passed through to run_ivector_common.sh
# (some of which are also used in this script directly).
# stage=0
nj=30

train_set=train
test_sets="dev"    #"dev eval"
gmm=mono        # this is the source gmm-dir that we'll use for alignments; it
                 # should have alignments for the specified training data.
num_threads_ubm=32
nnet3_affix=mono      # affix for exp dirs, e.g. it was _cleaned in tedlium.
tdnn_affix=1a  #affix for TDNN directory e.g. "1a" or "1b", in case we change the configuration.

# Options which are not passed through to run_ivector_common.sh
train_stage=-10
remove_egs=true
srand=0
reporting_email=
# set common_egs_dir to use previously dumped egs.
common_egs_dir=

source ./cmd.sh
. ./path.sh || { echo "Cannot source path.sh"; exit 1; }
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

# local/nnet3/run_ivector_common.sh --stage $stage --nj $nj \
#                                   --train-set $train_set --gmm $gmm \
#                                   --num-threads-ubm $num_threads_ubm \
#                                   --nnet3-affix "$nnet3_affix"

multi_L="MULLAN"
export GP_LANGUAGES="CZ FR GE PL PO RU SP SW"   #"CZ GE PL PO RU SP SW"
for LAN in $multi_L; do
  stage=0
  gmm_dir=exp/$LAN/${gmm}
  ali_dir=exp/$LAN/${gmm}_ali
  dir=exp/$LAN/nnet3${nnet3_affix}/tdnn${tdnn_affix}
  train_data_dir=data/$LAN/${train_set}

  utils/fix_data_dir.sh $train_data_dir
  for f in $train_data_dir/feats.scp $gmm_dir/graph_tgpr_sri/HCLG.fst \
      $ali_dir/ali.1.gz $gmm_dir/final.mdl; do
    (
    [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1
    ) &
  done

  if [ $stage -le 12 ]; then
    mkdir -p $dir
    echo "$0: creating neural net configs using the xconfig parser";

    num_targets=$(tree-info $gmm_dir/tree |grep num-pdfs|awk '{print $2}')

    mkdir -p $dir/configs
    cat <<EOF > $dir/configs/network.xconfig
    # input dim=100 name=ivector
    input dim=40 name=input

    # please note that it is important to have input layer with the name=input
    # as the layer immediately preceding the fixed-affine-layer to enable
    # the use of short notation for the descriptor
    fixed-affine-layer name=lda input=Append(-2,-1,0,1,2) affine-transform-file=$dir/configs/lda.mat
    # ,ReplaceIndex(ivector, t, 0)
    # the first splicing is moved before the lda layer, so no splicing here
    relu-renorm-layer name=tdnn1 dim=650
    relu-renorm-layer name=tdnn2 dim=650 input=Append(-1,0,1)
    relu-renorm-layer name=tdnn3 dim=650 input=Append(-1,0,1)
    relu-renorm-layer name=tdnn4 dim=650 input=Append(-3,0,3)
    relu-renorm-layer name=tdnn5 dim=650 input=Append(-6,-3,0)
    output-layer name=output dim=$num_targets max-change=1.5
EOF
    steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
  fi



  if [ $stage -le 13 ]; then
    if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
      utils/create_split_dir.pl \
       /export/b0{3,4,5,6}/$USER/kaldi-data/egs/tedlium-$(date +'%m_%d_%H_%M')/s5_r2/$dir/egs/storage $dir/egs/storage
    fi

    steps/nnet3/train_dnn.py --stage=$train_stage \
      --cmd="$decode_cmd" \
      --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
      --trainer.srand=$srand \
      --trainer.max-param-change=2.0 \
      --trainer.num-epochs=3 \
      --trainer.samples-per-iter=400000 \
      --trainer.optimization.num-jobs-initial=2 \
      --trainer.optimization.num-jobs-final=2 \
      --trainer.optimization.initial-effective-lrate=0.0015 \
      --trainer.optimization.final-effective-lrate=0.00015 \
      --trainer.optimization.minibatch-size=256,128 \
      --egs.dir="$common_egs_dir" \
      --cleanup.remove-egs=$remove_egs \
      --use-gpu=true \
      --feat-dir=$train_data_dir \
      --ali-dir=$ali_dir \
      --lang=data/$LAN/lang \
      --reporting.email="$reporting_email" \
      --dir=$dir  || exit 1;

  if [ $stage -le 14 ]; then
    # note: for TDNNs, looped decoding gives exactly the same results
    # as regular decoding, so there is no point in testing it separately.
    # We use regular decoding because it supports multi-threaded (we just
    # didn't create the binary for that, for looped decoding, so far).
    rm $dir/.error || true 2>/dev/null
    for SL in $GP_LANGUAGES; do
      mkdir -p $dir/$SL
      rm $dir/$SL/final.{mdl,occs}||true
      ln -s ../final.mdl $dir/$SL/final.mdl
      ln -s ../final.occs $dir/$SL/final.occs
      for lm_suffix in tgpr_sri; do 
        for data in $test_sets; do
          (
            data_affix=$(echo $data | sed s/test_//)
            nj=$(wc -l <data/$SL/${data}/spk2utt)
            for lmtype in tgpr_sri; do
              graph_dir=$dir/$SL/graph_${lmtype}
              mkdir -p $graph_dir
              utils/mkgraph.sh data/$LAN/$SL/lang_test_${lmtype} $dir \
              $graph_dir
              steps/nnet3/decode.sh --nj $nj --cmd "$decode_cmd"  --num-threads 4 \
                ${graph_dir} data/$SL/${data} ${dir}/$SL/decode_${lmtype}_${data_affix} || exit 1
            done
            
            steps/lmrescore.sh --cmd "$decode_cmd" data/$LAN/$SL/lang_test_{tgpr,tg}_sri \
              data/$SL/${data} ${dir}/$SL/decode_{tgpr_sri,tg_sri}_${data_affix} || exit 1
        
          ) || touch $dir/.error &
        done
        wait;
      done
    done  
    wait;
    [ -f $dir/.error ] && echo "$0: there was a problem while decoding" && exit 1

  
  fi &

done
wait;

echo "TDNN training and decoding finished"


exit 0;
