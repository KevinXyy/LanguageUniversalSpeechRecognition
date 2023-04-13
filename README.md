# LanguageUniversalSpeechRecognition
To make the scripts sucessfully run, make sure that Kaldi is installed, its source code and tools are maked according to the installation guidance in the official repository.


These scripts includes the steps of running both experiments. 
First we build monolingual monophone GMMs for all the languages by running: 
```
    sh run_mfcchires_mono.sh
```
This would prepare the data for each language for further experiments and generates a monophone GMM for each language mentioned the the GP_LANGUAGES variable. For generating a TDNN monolingual model with monophone alignments, run the script:
```
    sh local/nnet3/run_tdnn.sh
```

Then we need to build the multilingual shared phone model. In this stage since the data of each language is already split. We nned to combine the split data and generate the multilingual GMM to generate alignments first. The phone list consists of phones tagged with their language IDs. To buld the model, run:
```
    sh run_multilingual_mono.sh
```
For building the shared output TDNN model and decoding on valiadation and test set, run:
```
    sh local/nnet3/run_tdnn_mono.sh
```

For the private phone multilingual model, the data is keeps the same and the phone list is not merged across languages. The monophone alignments are generated using each language's monolingual monophone mdoel previously. Then run the TDNN with multiple language-specific languages and evaluation:
```
    sh local/nnet3/run_tdnn_multilingual.sh
```

