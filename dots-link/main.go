package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

func main() {
	env, err := NewEnv()
	if err != nil {
		errLine("%v", err)
		os.Exit(1)
	}

	root := &cobra.Command{
		Use:           "dots-link",
		Short:         "Dotfiles symlink manager",
		SilenceUsage:  true,
		SilenceErrors: true,
	}

	root.AddCommand(
		&cobra.Command{
			Use:   "status",
			Short: "Show link health for every manifest entry",
			Args:  cobra.NoArgs,
			RunE:  func(_ *cobra.Command, _ []string) error { return runStatus(env) },
		},
		&cobra.Command{
			Use:   "remove",
			Short: "Remove this host's managed symlinks (manifest untouched)",
			Args:  cobra.NoArgs,
			RunE:  func(_ *cobra.Command, _ []string) error { return runRemove(env) },
		},
		archiveCmd(env),
		syncCmd(env),
	)

	if err := root.Execute(); err != nil {
		errLine("%v", err)
		os.Exit(1)
	}
}

func archiveCmd(env *Env) *cobra.Command {
	var yes bool
	cmd := &cobra.Command{
		Use:   "archive <path>",
		Short: "Retire a config into archive/ and drop it from all manifests",
		Args:  cobra.ExactArgs(1),
		RunE:  func(_ *cobra.Command, args []string) error { return runArchive(env, args[0], yes) },
	}
	cmd.Flags().BoolVarP(&yes, "yes", "y", false, "skip the confirmation prompt")
	return cmd
}

func syncCmd(env *Env) *cobra.Command {
	var opts syncOpts
	var local, remote, interactive bool
	cmd := &cobra.Command{
		Use:   "sync",
		Short: "Pull remote changes and converge symlinks safely",
		Args:  cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			res, err := resolutionFromFlags(local, remote, interactive)
			if err != nil {
				return err
			}
			opts.resolution = res
			return runSync(env, opts)
		},
	}
	cmd.Flags().BoolVar(&opts.dryRun, "dry-run", false, "print the plan and exit; no changes")
	cmd.Flags().BoolVarP(&opts.yes, "yes", "y", false, "skip the confirmation prompt")
	cmd.Flags().BoolVar(&local, "local", false, "on conflict, local wins: absorb live files/links into the repo, then link")
	cmd.Flags().BoolVar(&remote, "remote", false, "on conflict, repo wins: replace live files/links with a repo link")
	cmd.Flags().BoolVar(&interactive, "it", false, "resolve each conflict interactively (local/remote/skip)")
	return cmd
}

// resolutionFromFlags turns the mutually-exclusive conflict flags into a single
// strategy, erroring if more than one is set.
func resolutionFromFlags(local, remote, interactive bool) (resolution, error) {
	n := 0
	for _, b := range []bool{local, remote, interactive} {
		if b {
			n++
		}
	}
	if n > 1 {
		return resReport, fmt.Errorf("use only one of --local, --remote, --it")
	}
	switch {
	case local:
		return resLocal, nil
	case remote:
		return resRemote, nil
	case interactive:
		return resInteractive, nil
	default:
		return resReport, nil
	}
}
