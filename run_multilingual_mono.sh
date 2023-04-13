#!/bin/bash -u

# Copyright 2012  Arnab Ghoshal

#
# Copyright 2016 by Idiap Research Institute, http://www.idiap.ch
#
# See the file COPYING for the licence associated with this software.
#
# Author(s):
#   Bogdan Vlasenko, February 2016
#


# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# This script shows the steps needed to build a recognizer for certain languages
# of the GlobalPhone corpus.
# !!! NOTE: The current recipe assumes that you have pre-built LMs.
echo "This shell script may run as-is on your system, but it is recommended
that you run the commands one by one by copying and pasting into the shell."
#exit 1;

[ -f cmd.sh ] && source ./cmd.sh || echo "cmd.sh not found. Jobs may not execute properly."

# CHECKING FOR AND INSTALLING REQUIRED TOOLS:
#  This recipe requires shorten (3.6.1) and sox (14.3.2).
#  If they are not found, the local/gp_install.sh script will install them.
#local/gp_check_tools.sh $PWD path.sh || exit 1;

. ./path.sh || { echo "Cannot source path.sh"; exit 1; }

# Set the locations of the GlobalPhone corpus and language models
GP_CORPUS=/group/corporapublic/global_phone
GP_LM=$PWD/language_models

# Set the languages that will actually be processed
export GP_LANGUAGES="CZ FR GE PL PO RU SP SW"
# GE RU "SW""
multi_L="MULLAN"
# The following data preparation step actually converts the audio files from
# shorten to WAV to take out the empty files and those with compression errors.
src_train=""

dest_train="data/$multi_L/train"

for L in $GP_LANGUAGES; do
  src_train="$src_train data/$L/train"

done
wait;
utils/combine_data.sh $dest_train $src_train

local/gp_merge_dict.sh --config-dir $PWD/conf $GP_CORPUS $GP_LANGUAGES || exit 1;
utils/prepare_lang.sh --position-dependent-phones true \
   data/$multi_L/local/dict "<unk>" data/$multi_L/local/lang_tmp data/$multi_L/lang \
   >& data/$multi_L/prepare_lang.log || exit 1;

# Convert the different available language models to FSTs, and create separate
# decoding configurations for each.
for L in $GP_LANGUAGES; do
  local/gp_format_multi_lm.sh --filter-vocab-sri true $GP_LM $L &
   
done
wait;
# Now make MFCC features.

mfccdir=mfcc/$multi_L

for x in train; do
  (
    utils/fix_data_dir.sh data/$multi_L/$x
    steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --nj 6 --cmd "$train_cmd" data/$multi_L/$x \
      exp/$multi_L/make_mfcc/$x $mfccdir;
    steps/compute_cmvn_stats.sh data/$multi_L/$x exp/$multi_L/make_mfcc/$x $mfccdir;
  ) &
done
wait;


mkdir -p exp/$multi_L/mono;
steps/train_mono.sh --nj 10 --cmd "$train_cmd" \
  data/$multi_L/train data/$multi_L/lang exp/$multi_L/mono >& exp/$multi_L/mono/train.log
wait;

for L in $GP_LANGUAGES; do
  utils/fix_data_dir.sh data/$L/dev
  utils/fix_data_dir.sh data/$L/eval
done
wait;

for L in $GP_LANGUAGES; do
  mkdir -p exp/$multi_L/mono/$L
  x=40
  rm exp/$multi_L/mono/$L/final.{mdl,occs}
  ln -s ../$x.mdl exp/$multi_L/mono/$L/final.mdl
  ln -s ../$x.occs exp/$multi_L/mono/$L/final.occs
  for lm_suffix in tgpr_sri; do
    (
      graph_dir=exp/$multi_L/mono/$L/graph_${lm_suffix}
      mkdir -p $graph_dir
      utils/mkgraph.sh data/$multi_L/$L/lang_test_${lm_suffix} exp/$multi_L/mono \
          $graph_dir
      steps/decode.sh --nj 5 --cmd "$decode_cmd" $graph_dir data/$L/dev \
          exp/$multi_L/mono/$L/decode_dev_${lm_suffix}
      steps/decode.sh --nj 5 --cmd "$decode_cmd" $graph_dir data/$L/eval \
          exp/$multi_L/mono/$L/decode_eval_${lm_suffix}
    ) &
  done

done
wait;

# Generate monophone alignments for the transcriptions

mkdir -p exp/$multi_L/mono_ali
steps/align_si.sh --nj 10 --cmd "$train_cmd" \
    data/$multi_L/train data/$multi_L/lang exp/$multi_L/mono exp/$multi_L/mono_ali \
    >& exp/$multi_L/mono_ali/align.log

wait;

