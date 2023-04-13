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
export GP_LANGUAGES="FR"    #"CZ FR GE PL PO RU SP SW"
# GE RU "SW""

# The following data preparation step actually converts the audio files from
# shorten to WAV to take out the empty files and those with compression errors.
local/gp_data_prep.sh --config-dir=$PWD/conf --corpus-dir=$GP_CORPUS --languages="$GP_LANGUAGES" || exit 1;
local/gp_dict_prep.sh --config-dir $PWD/conf $GP_CORPUS $GP_LANGUAGES || exit 1;

for L in $GP_LANGUAGES; do
 utils/prepare_lang.sh --position-dependent-phones true \
   data/$L/local/dict "<unk>" data/$L/local/lang_tmp data/$L/lang \
   >& data/$L/prepare_lang.log || exit 1;
done

# Convert the different available language models to FSTs, and create separate
# decoding configurations for each.
for L in $GP_LANGUAGES; do
   local/gp_format_lm.sh --filter-vocab-sri true $GP_LM $L &
   
done
wait
# Now make MFCC features.
for L in $GP_LANGUAGES; do
  mfccdir=mfcc/$L
  utils/fix_data_dir.sh data/$L/train
  utils/fix_data_dir.sh data/$L/dev
  utils/fix_data_dir.sh data/$L/eval
  for x in train dev eval; do
    (
      steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --nj 6 --cmd "$train_cmd" data/$L/$x \
        exp/$L/make_mfcc/$x $mfccdir;
      steps/compute_cmvn_stats.sh data/$L/$x exp/$L/make_mfcc/$x $mfccdir;
    ) &
  done
done
wait;


for L in $GP_LANGUAGES; do
  mkdir -p exp/$L/mono;
  steps/train_mono.sh --nj 10 --cmd "$train_cmd" \
    data/$L/train data/$L/lang exp/$L/mono >& exp/$L/mono/train.log &
done
wait;


for L in $GP_LANGUAGES; do
  for lm_suffix in tgpr_sri; do
    (
      graph_dir=exp/$L/mono/graph_${lm_suffix}
      mkdir -p $graph_dir
      utils/mkgraph.sh data/$L/lang_test_${lm_suffix} exp/$L/mono \
         $graph_dir

      steps/decode.sh --nj 5 --cmd "$decode_cmd" $graph_dir data/$L/dev \
         exp/$L/mono/decode_dev_${lm_suffix}
      steps/decode.sh --nj 5 --cmd "$decode_cmd" $graph_dir data/$L/eval \
         exp/$L/mono/decode_eval_${lm_suffix}
    ) &
  done
done

# Generate monophone alignments
for L in $GP_LANGUAGES; do
  (
    mkdir -p exp/$L/mono_ali
    steps/align_si.sh --nj 10 --cmd "$train_cmd" \
        data/$L/train data/$L/lang exp/$L/mono exp/$L/mono_ali \
        >& exp/$L/mono_ali/align.log
  ) &
done
wait;

