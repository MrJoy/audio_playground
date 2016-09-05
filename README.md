# Audio Playground

Playground for me to play with FFTs and CoreAudio.

This code was all written between 9pm and 2am while preparing for my wedding, so...  my apologies.


## Installation

After cloning this repo, run:

```bash
brew install fftw
bundle install
```

## Usage

To run the crude band-pass filter in interactive mode where you can tweak the parameters and hear the output:

```bash
# Plug in headphones!
# Turn volume *down* until you're running the processor, then turn it up to taste!

bin/sm-discover-audio
# Replace '39' below with the ID listed for 'Built-in Microphone' from above:
bin/sm-audio-processor --input-device=39 --map=0,1 --window=8192 --span=16 --mode=interactive
```

The audio will lag considerably due to the size of the sliding window / span parameters.  As my math is... not close to correct yet, reducing these parameters reduces the quality of the filtering considerably.


## Testing

```bash
bin/test.sh
```

This will run some simple regression tests to ensure that the filter behavior hasn't changed, using a variety of pure sine-wave recordings.  To see if the behavior has changed, do `git status` to see if any of the files in `test/results` have been changed.
