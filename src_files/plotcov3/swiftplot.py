"""Swift Biosciences Plotting Library
   Draft v0.0
   Jonathan Irish, 2018-07-31"""

import argparse
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

# Swift colors
swiftpurple = '#962878'
swiftblue = '#2D559B'
swiftlightblue = '#28aae1'
swiftorange = '#f56e1e'
swiftmagenta = '#eb0a6e'
swiftsuperlightblue = '#b9e6fa' 
swiftblack = '#5a5a5a'
swiftgrey = '#969696'
swiftgreen = '#8cc83c'

swiftpalette = [swiftpurple, swiftblue, swiftlightblue, swiftorange,
                swiftmagenta, swiftsuperlightblue, swiftblack, swiftgrey,
                swiftgreen]

# Plot functions

# plot MID family size histogram
def plotMIDfamsize_hist(counts, minfamsize=1, outfile=None):
    """Plot a histogram of MID family size from a collection of family size
       counts, optionally filter out counts below 'minfamsize',
       and optionally save plot to pdf file if 'outfile' provided"""

    adjcounts = [x for x in counts if x > minfamsize]

    # calculate mean family size and ajusted mean (famsz > 4)
    cmean = round(mean(counts), 2)
    adjmean = round(mean(adjcounts), 2)

    meanfamsz_str = r'$\mu$ = ' + str(cmean)
    adjmeanfamsz_str = r'adj. $\mu$ (family size > 2) = ' + str(adjmean)

    fig, ax = plt.subplots(figsize=(18,12))
    fig.patch.set_facecolor('0.92')
    ax.set_facecolor('0.92')
    ax.hist(adjcounts, edgecolor='black', bins=52, color=swiftpurple)
    ax.xaxis.set_major_locator(ticker.MultipleLocator(5))
    ax.spines['right'].set_visible(False)
    ax.spines['top'].set_visible(False)
    ax.spines['left'].set_linewidth(1.5)
    ax.spines['left'].set_color('black')
    ax.spines['bottom'].set_linewidth(1.5)
    ax.spines['bottom'].set_color('black')
    ax.set_xlabel("MID family size", fontsize=18)
    (_,ymx) = ax.get_ylim()
    (_,xmx) = ax.get_xlim()
    ax.set_title((outprefix + " MID family size distribution"), fontsize=24, fontweight='bold')
    ax.text(0.5*xmx, 0.8*ymx,meanfamsz_str, fontsize=18)
    ax.text(0.5*xmx, 0.7*ymx,adjmeanfamsz_str, fontsize=18)
    if outfile:
        fig.savefig(outprefix + "_MID_familysize_hist.pdf",
                    bbox_inches="tight", facecolor='0.92')

# plot general histogram in Swift colors
def plotSwift_hist(counts, title=None, xlabel=None):
    """Plot a histogram from a collection of counts"""

    fig, ax = plt.subplots(figsize=(18,12))
    fig.patch.set_facecolor('0.92')
    ax.set_facecolor('0.92')
    ax.hist(counts, edgecolor='black', color=swiftpurple)
    ax.xaxis.set_major_locator(ticker.MultipleLocator(5))
    ax.spines['right'].set_visible(False)
    ax.spines['top'].set_visible(False)
    ax.spines['left'].set_linewidth(1.5)
    ax.spines['left'].set_color('black')
    ax.spines['bottom'].set_linewidth(1.5)
    ax.spines['bottom'].set_color('black')
    if xlabel:
        ax.set_xlabel(xlabel, fontsize=18)
    if title:
        ax.set_title(title, fontsize=24, fontweight='bold')
    return (fig, ax)

#########################    TEST DATA    #####################################
# test files
testdir1 = "/mnt/ampdata/irish/MIDplots/plotinfiles/"
# input file column format: amplicon | mean_amp_coverage | gene_or_groupID
testf1 = testdir1 + \
         "EGFR-HD701-1_S61.mid_fam_counts2hist.txt"
###############################################################################

