
# check for incompatibilities

 aws eks list-insights --cluster-name eml-eks --profile eml-eks


 # Tool: kubent (kube-no-trouble)
sh -c "$(curl -sSL https://git.io/install-kubent)"

kubent

kubent > kubent-report.txt


# pluto (alternative to kubent)
## GitHub:
https://github.com/FairwindsOps/pluto