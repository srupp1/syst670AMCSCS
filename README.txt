To run the code, after Unzipping the folder, you can either use it via a local install of MATLAB (we tested 2023a) or you can use MATLABonline which we have access
via UMBC. If you log in using your UMBC information you can run MATLAB in your browser with no issues. We tested the code here using 2026a which seems to be the default.

There are 3 different views into the simulation that you can run, as well as a last command to get the output report

1. You can run main.m, either using the run button at the top of the MATLAB window, or simply, in the command line enter: main
	a) One note is that for this simulation, you need not keep the window open, if you close it the simulation will still run in the background, 
	   so if you do need to kill it, either CTRL-C or press the stop button.
	b) Notice that as the simulation runs, there will be print outs for every 10 runs, with a total elapsed time and ETA for completion

2. You can also run the v and v dashboard with the vvDashboard.m file or entering vvDashboard on the command line
	a) If you want to run the V and V suite in "fast mode" use vvDashboard('fast')
	b) In this case, if you kill the GUI, the simulation will not continue to run.

3. If you want to run a sensitivity analysis of the simulation, run sensitivityAnalysis from sensitivityAnalysis.m or via the command line.
	a) if you want to see how we vary the variables take a look a the .m file, the matrix defined by SWEEP shows all the variables that will be tested.
	   One thing asked about in the demo was how we kept all the variables with a baseline, and here you can see, it loads our default configuration, and the
	   simply modifies the output using the scales, except for the if you want absolute values (fleet size is an example of this). The way the simulation is build
	   any variable defined by the cfg object, we can easily run sensitivity analysis on. take a look at getDefaultConfig.m if you want to see what all can be modified

4. Finally you can run the full VandV suite for "score" using the exportVVReport.m file. Again this takes in the 'fast' argument if you want to use it.
	a) This is the final output that we use for reporting final values, and makes it very easy for anyone to understand the results of the simulation

A final note, the html report we used for our final documents is included here with the code. To view it all you need to do is download the file and then open it in your internet browser of choice and you should see it.
