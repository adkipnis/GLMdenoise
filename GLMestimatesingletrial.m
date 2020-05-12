function results = GLMestimatesingletrial(design,data,stimdur,tr,outputdir,opt)

% function results = GLMestimatesingletrial(design,data,stimdur,tr,outputdir,opt)
%
% <design> is the experimental design. There are two possible cases:
%   1. A where A is a matrix with dimensions time x conditions.
%      Each column should be zeros except for ones indicating condition onsets.
%   2. {A1 A2 A3 ... An} where each of the A's are like the previous case.
%      The different A's correspond to different runs, and different runs
%      can have different numbers of time points. However, all A's must have
%      the same number of conditions.
%   Note that we ultimately compute single-trial response estimates (one estimate for 
%   each condition onset), and these will be provided in chronological order. However,
%   by specifying that a given condition occurs more than one time over the course
%   of the experiment, this information can and will be used for cross-validation purposes.
% <data> is the time-series data with dimensions X x Y x Z x time or a cell vector of 
%   elements that are each X x Y x Z x time. XYZ can be collapsed such that the data 
%   are given as a 2D matrix (units x time), which is useful for surface-format data.
%   The dimensions of <data> should mirror that of <design>. For example, <design> and 
%   <data> should have the same number of runs, the same number of time points, etc.
%   <data> should not contain any NaNs. We automatically convert <data> to single 
%   format if not already in single format.
% <stimdur> is the duration of a trial in seconds. For example, 3.5 means that you 
%   expect the neural activity from a given trial to last for 3.5 s.
% <tr> is the sampling rate in seconds. For example, 1 means that we get a new
%   time point every 1 s. Note that <tr> applies to both <design> and <data>.
% <outputdir> (optional) is a directory to which files will be written. (If the
%   directory does not exist, we create it; if the directory already exists,
%   we delete its contents so we can start fresh.) If you set <outputdir>
%   to NaN, we will not create a directory and no files will be written.
%   Default is 'GLMestimatesingletrialoutputs' (created in the current working directory).
% <opt> (optional) is a struct with the following optional fields:
%
%   *** MAJOR, HIGH-LEVEL FLAGS ***
%
%   <wantlibrary> (optional) is
%     0 means use an assumed HRF
%     1 means determine the best HRF for each voxel using the library-of-HRFs approach
%     Default: 1.
%   <wantglmdenoise> (optional) is
%     0 means do not perform GLMdenoise
%     1 means perform GLMdenoise
%     Default: 1.
%   <wantfracridge> (optional) is
%     0 means do not perform ridge regression
%     1 means perform ridge regression
%     Default: 1.
%   <chunknum> (optional) is the number of voxels that we will process at the same time.
%     This number should be large in order to speed computation, but should not be so
%     large that you run out of RAM. Default: 50000.
%   <xvalscheme> (optional) is a cell vector of vectors of run indices, indicating the
%     cross-validation scheme. For example, if we have 8 runs, we could use
%     {[1 2] [3 4] [5 6] [7 8]} which indicates to do 4 folds of cross-validation, 
%     first holding out the 1st and 2nd runs, then the 3rd and 4th runs, etc.
%     Default: {[1] [2] [3] ... [n]} where n is the number of runs.
%
%   *** I/O FLAGS ***
%
%   <wantfileoutputs> (optional) is a logical vector [A B C D] indicating which of the
%     four model types to save to disk (assuming that they are computed).
%     A = 0/1 for saving the results of the ONOFF model
%     B = 0/1 for saving the results of the FITHRF model
%     C = 0/1 for saving the results of the FITHRF_GLMDENOISE model
%     D = 0/1 for saving the results of the FITHRF_GLMDENOISE_RR model
%     Default: [1 1 1 1] which means save all computed results to disk.
%   <wantmemoryoutputs> (optional) is a logical vector [A B C D] indicating which of the
%     four model types to return in the output <results>. The user must be careful with this,
%     as large datasets can require a lot of RAM. If you do not request the various model types,
%     they will be cleared from memory (but still potentially saved to disk).
%     Default: [0 0 0 1] which means return only the final type-D model.
%
%   *** GLM FLAGS ***
%
%   <extraregressors> (optional) is time x regressors or a cell vector
%     of elements that are each time x regressors. The dimensions of 
%     <extraregressors> should mirror that of <design> (i.e. same number of 
%     runs, same number of time points). The number of extra regressors 
%     does not have to be the same across runs, and each run can have zero 
%     or more extra regressors. If [] or not supplied, we do 
%     not use extra regressors in the model.
%   <maxpolydeg> (optional) is a non-negative integer with the maximum 
%     polynomial degree to use for polynomial nuisance functions, which
%     are used to capture low-frequency noise fluctuations in each run.
%     Can be a vector with length equal to the number of runs (this
%     allows you to specify different degrees for different runs).  
%     Default is to use round(L/2) for each run where L is the 
%     duration in minutes of a given run.
%   <wantpercentbold> (optional) is whether to convert amplitude estimates
%     to percent BOLD change. This is done as the very last step, and is
%     accomplished by dividing by the absolute value of 'meanvol' and 
%     multiplying by 100. (The absolute value prevents negative values in
%     'meanvol' from flipping the sign.) Default: 1.
%
%   *** HRF FLAGS ***
% 
%   <hrftoassume> (optional) is time x 1 with an assumed HRF that characterizes the evoked
%     response to each trial. We automatically divide by the maximum value so that the 
%     peak is equal to 1. Default is to generate a canonical HRF (see getcanonicalhrf.m). 
%     Note that the HRF supplied in <hrftoassume> is used in only two instances: 
%     (1) it is used for the simple ONOFF type-A model, and (2) if the user sets 
%     <wantlibrary> to 0, it is also used for the type-B, type-C, and type-D models.
%   <hrflibrary> (optional) is time x H with H different HRFs to choose from for the
%     library-of-HRFs approach. We automatically normalize each HRF to peak at 1. 
%     Default is to generate a library of 20 HRFs (see getcanonicalhrflibrary.m). 
%     Note that if <wantlibrary> is 0, <hrflibrary> is clobbered with the contents
%     of <hrftoassume>, which in effect causes a single assumed HRF to be used.
%
%   *** MODEL TYPE A (ONOFF) FLAGS ***
%
%   (none)
%
%   *** MODEL TYPE B (FITHRF) FLAGS ***
%   
%   <wantlss> (optional) is 0/1 indicating whether "least-squares-separate" estimates
%     are desired. If 1, then the type-B model will be estimated using the least-squares-
%     separate method (as opposed to ordinary least squares). Default: 0.
%
%   *** MODEL TYPE C (FITHRF_GLMDENOISE) FLAGS ***
% 
%   <numpcstotry> (optional) is a non-negative integer indicating the maximum
%     number of PCs to enter into the model. Default: 10.
%   <brainthresh> (optional) is [A B] where A is a percentile for voxel intensity 
%     values and B is a fraction to apply to the percentile. These parameters
%     are used in the selection of the noise pool. Default: [99 0.1].
%   <brainR2> (optional) is an R^2 value (percentage). After fitting the type-A model,
%     voxels whose R^2 is below this value are allowed to enter the noise pool.
%     Default is [] which means to automatically determine a good value.
%   <brainexclude> (optional) is X x Y x Z (or XYZ x 1) with 1s indicating voxels to 
%     specifically exclude when selecting the noise pool. 0 means all voxels can be 
%     potentially chosen. Default: 0.
%   <pcR2cutoff> (optional) is an R^2 value (percentage). To decide the number
%     of PCs to include, we examine a subset of the available voxels. Specifically, 
%     we examine voxels whose type-A model R^2 is above <pcR2cutoff>. Default is []
%     which means to automatically determine a good value.
%   <pcR2cutoffmask> (optional) is X x Y x Z (or XYZ x 1) with 1s indicating all possible
%     voxels to consider when selecting the subset of voxels. 1 means all voxels 
%     can be potentially selected. Default: 1.
%   <pcstop> (optional) is
%     A: a number greater than or equal to 1 indicating when to stop adding PCs 
%        into the model. For example, 1.05 means that if the cross-validation 
%        performance with the current number of PCs is within 5% of the maximum 
%        observed, then use that number of PCs. (Performance is measured 
%        relative to the case of 0 PCs.) When <pcstop> is 1, the selection 
%        strategy reduces to simply choosing the PC number that achieves
%        the maximum. The advantage of stopping early is to achieve a selection
%        strategy that is robust to noise and shallow performance curves and 
%        that avoids overfitting.
%    -B: where B is the number of PCs to use for the final model. B can be any 
%        integer between 0 and opt.numpcstotry. Note that if -B case is used, 
%        cross-validation is NOT performed for the type-C model, and instead we
%        blindly use B PCs.
%     Default: 1.05.
%
%   *** MODEL TYPE D (FITHRF_GLMDENOISE_RR) FLAGS ***
%
%   <fracs> (optional) is a vector of fractions that are greater than 0
%     and less than or equal to 1. We automatically sort in descending order and 
%     ensure the fractions are unique. These fractions indicate the regularization
%     levels to evaluate using fractional ridge regression (fracridge) and
%     cross-validation. Default: fliplr(.05:.05:1). A special case is when <fracs>
%     is specified as a single scalar value. In this case, cross-validation 
%     is NOT performed for the type-D model, and we instead blindly use
%     the supplied fractional value for the type-D model.
%   <wantautoscale> (optional) is whether to automatically scale and offset
%     the model estimates from the type-D model to best match the unregularized
%     estimates. Default: 1.
%
% This function computes up to four model outputs (called type-A (ONOFF), 
% type-B (FITHRF), type-C (FITHRF_GLMDENOISE), and type-D (FITHRF_GLMDENOISE_RR)),
% and either saves the model outputs to disk, or returns them in <results>, or both,
% depending on what the user specifies.
%
% There are a variety of cases that you can achieve. Here are some examples:
%
% - wantlibrary=1, wantglmdenoise=1, wantfracridge=1 [Default]
%     A = simple ONOFF model
%     B = single-trial estimates using a tailored HRF for every voxel
%     C = like B but with GLMdenoise regressors added into the model
%     D = like C but with ridge regression regularization tailored to each voxel
%
% - wantlibrary=0
%     A fixed assumed HRF is used in all model types.
%
% - wantglmdenoise=0, wantfracridge=0
%     Model types C and D are not computed.
%
% - wantglmdenoise=0, wantfracridge=1
%     Model type C is not computed; model type D is computed using 0 GLMdenoise regressors.
%
% - wantglmdenoise=1, wantfracridge=0
%     Model type C is computed; model type D is not computed.
%
% - wantlss=1
%     Model type B is computed, but using least-squares-separate instead of OLS.
%     Other model types, if computed, use OLS.
%
% Note that if you set wantglmdenoise=1, you MUST have repeats of conditions and
% an associated cross-validation scheme (<opt.xvalscheme>), UNLESS you specify
% opt.pcstop = -B. In other words, you can perform wantglmdenoise without any 
% cross-validation, but you need to provide opt.pcstop = -B.
%
% Note that if you set wantfracridge=1, you MUST have repeats of conditions and
% an associated cross-validation scheme (<opt.xvalscheme>), UNLESS you specify
% a single scalar opt.fracs. In other words, you can perform wantfracridge 
% without any cross-validation, but you need to provide opt.fracs as a scalar.
%
% OUTPUTS:
%
% There are various outputs for each of the four model types:
%
% <modelmd> is either
%   (1) the HRF (time x 1) and ON-OFF beta weights (X x Y x Z)
%   (2) the full set of single-trial beta weights (X x Y x Z x TRIALS)
% <R2> is model accuracy expressed in terms of R^2 (percentage).
% <R2run> is R2 separated by run
% <meanvol> is the mean of all volumes
% <FitHRFR2> is the R2 for each of the different HRFs in the library
% <FitHRFR2run> is separated by run
% <HRFindex> is the 1-index of the best HRF
% <HRFindexrun> is separated by run
% <totalbadness> is cross-validation results for GLMdenoise
% <xvaltrend> is the summary GLMdenoise cross-validation result on which pcnum selection is done
% <noisepool> indicates voxels that were selected for the noise pool
% <pcregressors> indicates the full set of candidate GLMdenoise regressors that were found
% <pcnum> is the number of PCs that were selected for the final model
% <FRACvalue> is the fractional regularization level chosen for each voxel
% <scaleoffset> is the scale and offset applied to RR estimates to best match the unregularized result
%
% History:
% - 2020/05/12 - Initial version. Beta version. Use with caution.

%% %%%%%%%%%%%%%%%%%%% DEAL WITH INPUTS

% massage <design> and sanity-check it
if ~iscell(design)
  design = {design};
end
numcond = size(design{1},2);
for p=1:length(design)
  assert(all(ismember(design{p}(:),[0 1])),'<design> must consist of 0s and 1s');
  assert(size(design{p},2)==numcond,'all runs in <design> should have the same number of conditions');
  design{p} = full(design{p});
end

% massage <data> and sanity-check it
if ~iscell(data)
  data = {data};
end
for p=1:length(data)
  if ~isa(data{p},'single')
    fprintf('WARNING: Converting data in run %d to single format (consider doing this before the function call to reduce memory usage).\n',p);
    data{p} = single(data{p});
  end
end
assert(all(isfinite(data{1}(:))),'We checked the first run and found some non-finite values (e.g. NaN, Inf). Please fix and re-run.');
assert(length(design)==length(data),'<design> and <data> should have the same number of runs');

% calc
numruns = length(design);
is3d = size(data{1},4) > 1;  % is this the X Y Z T case?
if ~is3d
  for p=1:length(data)
    data{p} = reshape(data{p},size(data{p},1),1,1,[]);  % force to XYZ x 1 x 1 x T for convenience
  end
end
dimdata = 3;  % how many of the first dimensions have data
dimtime = 4;  % the dimension with time points
numvoxels = prod(sizefull(data{1},3));  % total number of units

% check number of time points and truncate if necessary
for p=1:length(data)
  if size(data{p},4) > size(design{p},1)
    fprintf('WARNING: run %d has more time points in <data> than <design>. We are truncating <data>.\n',p);
    data{p} = data{p}(:,:,:,1:size(design{p},1));
  end
  if size(data{p},4) < size(design{p},1)
    fprintf('WARNING: run %d has more time points in <design> than <data>. We are truncating <design>.\n',p);
    design{p} = design{p}(1:size(data{p},4),:);
  end
end

% inputs
if ~exist('outputdir','var') || isempty(outputdir)
  outputdir = 'GLMestimatesingletrialoutputs';
end
if ~exist('opt','var') || isempty(opt)
  opt = struct();
end
if ~isfield(opt,'wantlibrary') || isempty(opt.wantlibrary)
  opt.wantlibrary = 1;
end
if ~isfield(opt,'wantglmdenoise') || isempty(opt.wantglmdenoise)
  opt.wantglmdenoise = 1;
end
if ~isfield(opt,'wantfracridge') || isempty(opt.wantfracridge)
  opt.wantfracridge = 1;
end
if ~isfield(opt,'chunknum') || isempty(opt.chunknum)
  opt.chunknum = 50000;
end
if ~isfield(opt,'xvalscheme') || isempty(opt.xvalscheme)
  opt.xvalscheme = num2cell(1:numruns);
end
if ~isfield(opt,'wantfileoutputs') || isempty(opt.wantfileoutputs)
  opt.wantfileoutputs = [1 1 1 1];
end
if ~isfield(opt,'wantmemoryoutputs') || isempty(opt.wantmemoryoutputs)
  opt.wantmemoryoutputs = [0 0 0 1];
end
if ~isfield(opt,'extraregressors') || isempty(opt.extraregressors)
  opt.extraregressors = cell(1,numruns);
end
if ~isfield(opt,'maxpolydeg') || isempty(opt.maxpolydeg)
  opt.maxpolydeg = zeros(1,numruns);
  for p=1:numruns
    opt.maxpolydeg(p) = round(((size(data{p},dimtime)*tr)/60)/2);
  end
end
if ~isfield(opt,'wantpercentbold') || isempty(opt.wantpercentbold)
  opt.wantpercentbold = 1;
end
if ~isfield(opt,'hrftoassume') || isempty(opt.hrftoassume)
  opt.hrftoassume = normalizemax(getcanonicalhrf(stimdur,tr)');
end
if ~isfield(opt,'hrflibrary') || isempty(opt.hrflibrary)
  opt.hrflibrary = getcanonicalhrflibrary(stimdur,tr)';
end
if ~isfield(opt,'wantlss') || isempty(opt.wantlss)
  opt.wantlss = 0;
end
if ~isfield(opt,'numpcstotry') || isempty(opt.numpcstotry)
  opt.numpcstotry = 10;
end
if ~isfield(opt,'brainthresh') || isempty(opt.brainthresh)
  opt.brainthresh = [99 0.1];
end
if ~isfield(opt,'brainR2') || isempty(opt.brainR2)
  opt.brainR2 = [];
end
if ~isfield(opt,'brainexclude') || isempty(opt.brainexclude)
  opt.brainexclude = 0;
end
if ~isfield(opt,'pcR2cutoff') || isempty(opt.pcR2cutoff)
  opt.pcR2cutoff = [];
end
if ~isfield(opt,'pcR2cutoffmask') || isempty(opt.pcR2cutoffmask)
  opt.pcR2cutoffmask = 1;
end
if ~isfield(opt,'pcstop') || isempty(opt.pcstop)
  opt.pcstop = 1.05;
end
if ~isfield(opt,'fracs') || isempty(opt.fracs)
  opt.fracs = fliplr(.05:.05:1);
end
if ~isfield(opt,'wantautoscale') || isempty(opt.wantautoscale)
  opt.wantautoscale = 1;
end

% deal with length issues and other miscellaneous things
if length(opt.maxpolydeg) == 1
  opt.maxpolydeg = repmat(opt.maxpolydeg,[1 numruns]);
end
opt.hrftoassume = normalizemax(opt.hrftoassume);
opt.hrflibrary = normalizemax(opt.hrflibrary,1);
opt.fracs = sort(unique(opt.fracs),'descend');
assert(all(opt.fracs>0),'fracs must be greater than 0');
assert(all(opt.fracs<=1),'fracs must be less than or equal to 1');
wantfig = ischar(outputdir);  % if outputdir is not NaN, we want figures

% deal with output directory
if ischar(outputdir)
  rmdirquiet(outputdir);
  mkdirquiet(outputdir);
end
if any(opt.wantfileoutputs)
  assert(ischar(outputdir),'you must specify an <outputdir> to get file outputs');
end

% deal with special library stuff
if opt.wantlibrary==0
  opt.hrflibrary = opt.hrftoassume;
end

% calc
nx = size(data{1},1);
ny = size(data{1},2);
nz = size(data{1},3);
nh = size(opt.hrflibrary,2);

% figure out chunking scheme
chunks = chunking(1:nx,ceil(nx/ceil(numvoxels/opt.chunknum)));

% deal with special cases
if opt.wantglmdenoise==1
  assert(any(opt.wantfileoutputs(3:4)==1) || any(opt.wantmemoryoutputs(3:4)==1), ...
         '<wantglmdenoise> is 1, but you did not request type C nor type D');
end
if opt.wantfracridge==1
  assert(opt.wantfileoutputs(4)==1 || opt.wantmemoryoutputs(4)==1, ...
         '<wantfracridge> is 1, but you did not request type D');
end
if opt.wantlss==1
  assert(opt.wantfileoutputs(2)==1 || opt.wantmemoryoutputs(2)==1, ...
         '<wantlss> is 1, but you did not request type B');
end

% initialize output
results = {};

%% %%%%%%%%%%%%%%%%%%% PRE-PROCESSING FOR THE EXPERIMENTAL DESIGN

% calculate the number of trials
numtrialrun = cellfun(@(x) sum(x(:)),design);  % number of trials in each run
numtrials = sum(numtrialrun);  % number of total trials

% create a single-trial design matrix and calculate a bunch of extra information
designSINGLE = {};
cnt = 0;
stimorder = [];                   % 1 x numtrials indicating which condition each trial belongs to 
validcolumns = cell(1,numruns);   % each element is the vector of trial indices associated with the run
stimix = cell(1,numruns);         % each element is the vector of actual condition numbers occurring with a given run
for p=1:length(design)
  designSINGLE{p} = zeros(size(design{p},1),numtrials);
  for q=1:size(design{p},1)
    temp = find(design{p}(q,:));
    if ~isempty(temp)
      cnt = cnt + 1;
      designSINGLE{p}(q,cnt) = 1;
      stimorder = [stimorder temp];
      validcolumns{p} = [validcolumns{p} cnt];
    end
  end
  stimix{p} = stimorder(validcolumns{p});
end

%% %%%%%%%%%%%%%%%%%%% FIT TYPE-A MODEL [ON-OFF]

% The approach:
% (1) Every stimulus is treated as the same.
% (2) We assume the HRF.

% define
whmodel = 1;

% collapse all conditions and fit
fprintf('*** FITTING TYPE-A MODEL (ONOFF) ***\n');
design0 = cellfun(@(x) sum(x,2),design,'UniformOutput',0);
results0 = GLMestimatemodel(design0,data,stimdur,tr,'assume',opt.hrftoassume,0, ...
                            struct('extraregressors',{opt.extraregressors}, ...
                                   'maxpolydeg',opt.maxpolydeg, ...
                                   'wantpercentbold',opt.wantpercentbold, ...
                                   'suppressoutput',1));

% remove unnecessary outputs
results0 = rmfield(results0,{'models' 'modelse' 'signal' 'noise' 'SNR' 'hrffitvoxels' 'inputs'});

% record some special critical outputs
onoffR2 = results0.R2;
meanvol = results0.meanvol;

% save to disk if desired
if opt.wantfileoutputs(whmodel)==1
  file0 = fullfile(outputdir,'TYPEA_ONOFF.mat');
  fprintf('*** Saving results to %s. ***\n',file0);
  save(file0,'-struct','results0','-v7.3');
end

% figures?
if wantfig && is3d
  imwrite(uint8(255*makeimagestack(onoffR2,[0 100]).^0.5),hot(256),fullfile(outputdir,'onoffR2.png'));
  imwrite(uint8(255*makeimagestack(meanvol,1)),gray(256),          fullfile(outputdir,'meanvol.png'));
end

% preserve in memory if desired, and then clean up
if opt.wantmemoryoutputs(whmodel)==1
  results{whmodel} = results0;
end
clear results0;

%% %%%%%%%%%%%%%%%%%%% DETERMINE THRESHOLDS

thresh = findtailthreshold(onoffR2(:),wantfig);
if wantfig
  figurewrite('onoffR2hist',[],[],outputdir);
end
if isempty(opt.brainR2)
  opt.brainR2 = thresh;
end
if isempty(opt.pcR2cutoff)
  opt.pcR2cutoff = thresh;
end

%% %%%%%%%%%%%%%%%%%%% FIT TYPE-B MODEL [FITHRF]

% The approach:
% (1) Fit single trials.
% (2) Evaluate the library of HRFs (or the single assumed HRF). Choose based on R2 for each voxel.

% if the user does not want file output nor memory output AND if the number of HRFs to choose
% from is just 1, we can short-circuit this whole endeavor!
if opt.wantfileoutputs(2)==0 && opt.wantmemoryoutputs(2)==0 && size(opt.hrflibrary,2)==1

  % short-circuit all of the work
  HRFindex = ones(nx,ny,nz);  % easy peasy
  
else

  % define
  whmodel = 2;

  % initialize
  FitHRFR2 =    zeros(nx,ny,nz,nh,'single');          % X x Y x Z x HRFs with R2 values (all runs)
  FitHRFR2run = zeros(nx,ny,nz,numruns,nh,'single');  % X x Y x Z x runs x HRFs with R2 separated by runs
  modelmd =     zeros(nx,ny,nz,numtrials,'single');   % X x Y x Z x trialbetas

  % loop over chunks
  fprintf('*** FITTING TYPE-B MODEL (FITHRF) ***\n');
  for z=1:length(chunks)
    fprintf('working on chunk %d of %d.\n',z,length(chunks));

    % do the fitting and accumulate all the betas
    modelmd0 = zeros(length(chunks{z}),ny,nz,numtrials,nh,'single');  % someX x Y x Z x trialbetas x HRFs
    for p=1:size(opt.hrflibrary,2)
      results0 = GLMestimatemodel(designSINGLE,cellfun(@(x) x(chunks{z},:,:,:),data,'UniformOutput',0), ...
                                  stimdur,tr,'assume',opt.hrflibrary(:,p),0, ...
                                  struct('extraregressors',{opt.extraregressors}, ...
                                         'maxpolydeg',opt.maxpolydeg, ...
                                         'wantpercentbold',opt.wantpercentbold, ...
                                         'suppressoutput',1));
      FitHRFR2(chunks{z},:,:,p) = results0.R2;
      FitHRFR2run(chunks{z},:,:,:,p) = results0.R2run;
      modelmd0(:,:,:,:,p) = results0.modelmd{2};
      clear results0;
    end
  
    % keep only the betas we want
    [~,ii] = max(FitHRFR2(chunks{z},:,:,:),[],4);
    modelmd(chunks{z},:,:,:) = matrixindex(modelmd0,repmat(ii,[1 1 1 size(modelmd0,4)]),5);
    clear modelmd0;

  end

  % use R2 to select the best HRF for each voxel
  [R2,HRFindex] = max(FitHRFR2,[],4);  % HRFindex is X x Y x Z

  % also, use R2 from each run to select best HRF
  [~,HRFindexrun] = max(FitHRFR2run,[],5);

  % using each voxel's best HRF, what are the corresponding R2run values?
  R2run = matrixindex(FitHRFR2run,repmat(HRFindex,[1 1 1 size(FitHRFR2run,4)]),5);  % R2run is X x Y x Z x runs

  %% %%%%%%%% FIT TYPE-B MODEL (LSS) INTERLUDE BEGIN

  % if opt.wantlss, we have to use the determined HRFindex and re-fit the entire dataset
  % using LSS estimation. this will simply replace 'modelmd' with a new version.
  % so that's what we have to do here.

  if opt.wantlss

    % initalize
    modelmd = zeros(nx*ny*nz,numtrials,'single');     % X*Y*Z x trialbetas  [the final beta estimates]

    % loop over chunks
    fprintf('*** FITTING TYPE-B MODEL (FITHRF but with LSS estimation) ***\n');
    for z=1:length(chunks)
      fprintf('working on chunk %d of %d.\n',z,length(chunks));
  
      % loop over possible HRFs
      for hh=1:size(opt.hrflibrary,2)
  
        % figure out which voxels to process.
        % this will be a vector of indices into the small chunk that we are processing.
        % our goal is to fully process this set of voxels!
        goodix = flatten(find(HRFindex(chunks{z},:,:)==hh));
      
        % extract the data we want to process.
        data0 = cellfun(@(x) subscript(squish(x(chunks{z},:,:,:),3),{goodix ':'}),data,'UniformOutput',0);
      
        % calculate the corresponding indices relative to the full volume
        temp = zeros(size(HRFindex));
        temp(chunks{z},:,:) = 1;
        relix = subscript(find(temp),goodix);
  
        % define options
        optA = struct('extraregressors',{opt.extraregressors}, ...
                      'maxpolydeg',opt.maxpolydeg, ...
                      'wantpercentbold',opt.wantpercentbold, ...
                      'suppressoutput',1);

        % do the GLM
        cnt = 0;
        for rrr=1:length(designSINGLE)  % each run
          for ccc=1:numtrialrun(rrr)    % each trial
            designtemp = designSINGLE{rrr};
            designtemp = [designtemp(:,cnt+ccc) sum(designtemp(:,setdiff(1:size(designtemp,2),cnt+ccc)),2)];
            [results0,cache] = GLMestimatemodel(designtemp,data0{rrr}, ...
                                        stimdur,tr,'assume',opt.hrflibrary(:,hh),0,optA);
            modelmd(relix,cnt+ccc) = results0.modelmd{2}(:,1);
            clear results0;
          end
          cnt = cnt + numtrialrun(rrr);
        end
  
      end
    
    end
  
    % deal with dimensions
    modelmd = reshape(modelmd,[nx ny nz numtrials]);

  end

  %% %%%%%%%% FIT TYPE-B MODEL (LSS) INTERLUDE END

  % save to disk if desired
  allvars = {'FitHRFR2','FitHRFR2run','HRFindex','HRFindexrun','R2','R2run','modelmd','meanvol'};
  if opt.wantfileoutputs(whmodel)==1
    file0 = fullfile(outputdir,'TYPEB_FITHRF.mat');
    fprintf('*** Saving results to %s. ***\n',file0);
    save(file0,allvars{:},'-v7.3');
  end

  % figures?
  if wantfig && is3d
    imwrite(uint8(255*makeimagestack(HRFindex,[1 nh])),jet(256),fullfile(outputdir,'HRFindex.png'));
  end

  % preserve in memory if desired, and then clean up
  if opt.wantmemoryoutputs(whmodel)==1
    results{whmodel} = struct;
    for p=1:length(allvars)
      results{whmodel}.(allvars{p}) = eval(allvars{p});
    end
  end
  clear FitHRFR2 FitHRFR2run R2 R2run modelmd;  % Note that we keep HRFindex and HRFindexrun around!!

end

%% %%%%%%%%%%%%%%%%%%% COMPUTE GLMDENOISE REGRESSORS

% if the user does not want to perform GLMdenoise, we can just skip all of this
if opt.wantglmdenoise==0

  % just create placeholders
  pcregressors = {};
  noisepool = [];

else

  % figure out the noise pool
  thresh = prctile(meanvol(:),opt.brainthresh(1))*opt.brainthresh(2);    % threshold for non-brain voxels
  bright = meanvol > thresh;                                             % logical indicating voxels that are bright (brain voxels)
  badR2 = onoffR2 < opt.brainR2;                                         % logical indicating voxels with poor R2
  noisepool = bright & badR2 & ~opt.brainexclude;                        % logical indicating voxels that satisfy all criteria

  % determine noise regressors
  pcregressors = {};
  fprintf('*** DETERMINING GLMDENOISE REGRESSORS ***\n');
  for p=1:length(data)

    % extract the time-series data for the noise pool
    temp = subscript(squish(data{p},dimdata),{find(noisepool) ':'})';  % time x voxels

    % project out polynomials from the data
    temp = projectionmatrix(constructpolynomialmatrix(size(temp,1),0:opt.maxpolydeg(p))) * temp;

    % unit-length normalize each time-series (ignoring any time-series that are all 0)
    [temp,len] = unitlengthfast(temp,1);
    temp = temp(:,len~=0);

    % perform SVD and select the top PCs
    [u,s,v] = svds(double(temp*temp'),opt.numpcstotry);
    u = bsxfun(@rdivide,u,std(u,[],1));  % scale so that std is 1
    pcregressors{p} = cast(u,'single');

  end
  clear temp len u s v;

end

%% %%%%%%%%%%%%%%%%%%% CROSS-VALIDATE TO FIGURE OUT NUMBER OF GLMDENOISE REGRESSORS

% if the user does not want GLMdenoise, just set some dummy values
if opt.wantglmdenoise==0
  pcnum = 0;
  xvaltrend = [];
  totalbadness = [];

% in this case, the user decides (and we can skip the cross-validation)
elseif opt.pcstop <= 0
  pcnum = -opt.pcstop;
  xvaltrend = [];
  totalbadness = [];

% otherwise, we have to do a lot of work
else
  
  % initialize
  totalbadness = zeros(nx*ny*nz,1+opt.numpcstotry,'single');    % X * Y * Z x 1+npc  [squared beta error for different numbers of PCs]
  
  % loop over chunks
  fprintf('*** CROSS-VALIDATING DIFFERENT NUMBERS OF REGRESSORS ***\n');
  for z=1:length(chunks)
    fprintf('working on chunk %d of %d.\n',z,length(chunks));

    % loop over possible HRFs
    for hh=1:size(opt.hrflibrary,2)
  
      % figure out which voxels to process.
      % this will be a vector of indices into the small chunk that we are processing.
      % our goal is to fully process this set of voxels!
      goodix = flatten(find(HRFindex(chunks{z},:,:)==hh));
      
      % extract the data we want to process.
      data0 = cellfun(@(x) subscript(squish(x(chunks{z},:,:,:),3),{goodix ':'}),data,'UniformOutput',0);
      
      % calculate the corresponding indices relative to the full volume
      temp = zeros(size(HRFindex));
      temp(chunks{z},:,:) = 1;
      relix = subscript(find(temp),goodix);
  
      % perform GLMdenoise
      clear results0;
      for ll=0:opt.numpcstotry
  
        % define options
        optA = struct('maxpolydeg',opt.maxpolydeg, ...
                      'wantpercentbold',0, ...
                      'suppressoutput',1);
        optA.extraregressors = cell(1,length(data0));
        if ll>0
          for rr=1:length(data0)
            optA.extraregressors{rr} = cat(2,optA.extraregressors{rr},pcregressors{rr}(:,1:ll));
          end
        end
        
        % do the GLM
        [results0(ll+1),cache] = GLMestimatemodel(designSINGLE,data0, ...
                                   stimdur,tr,'assume',opt.hrflibrary(:,hh),0,optA);
  
        % save some memory
        results0(ll+1).models = [];
        results0(ll+1).modelse = [];
      
      end
  
      % compute the cross-validation performance values
      totalbadness(relix,:) = calcbadness(opt.xvalscheme,validcolumns,stimix,results0);  % voxels x regularization levels
      clear results0;
  
    end
    
  end

  % compute xvaltrend
  ix = find((onoffR2(:) > opt.pcR2cutoff) & (opt.pcR2cutoffmask(:)));  % vector of indices
  if isempty(ix)
    fprintf('Warning: no voxels passed the pcR2cutoff and pcR2cutoffmask criteria. Using the best 100 voxels.\n');
    if isequal(opt.pcR2cutoffmask,1)
      ix2 = find(ones(size(onoffR2)));
    else
      ix2 = find(opt.pcR2cutoffmask==1);
    end
    assert(length(ix2) > 0,'no voxels are in pcR2cutoffmask');
    [~,ix3] = sort(onoffR2(ix2),'descend');
    num = min(100,length(ix2));
    ix = ix2(ix3(1:num));
  end
  xvaltrend = -median(totalbadness(ix,:),1);  % NOTE: sign flip so that high is good
  assert(all(isfinite(xvaltrend)));
  
  % choose number of PCs
  chosen = 0;  % this is the fall-back
  curve = xvaltrend - xvaltrend(1);  % this is the performance curve that starts at 0 (corresponding to 0 PCs)
  mx = max(curve);                   % store the maximum of the curve
  best = -Inf;                       % initialize (this will hold the best performance observed thus far)
  for p=0:opt.numpcstotry
  
    % if better than best so far
    if curve(1+p) > best
  
      % record this number of PCs as the best
      chosen = p;
      best = curve(1+p);
    
      % if we are within opt.pcstop of the max, then we stop.
      if best*opt.pcstop >= mx
        break;
      end
    
    end
  
  end
  
  % record the number of PCs
  pcnum = chosen;
  
  % deal with dimensions
  totalbadness = reshape(totalbadness,nx,ny,nz,[]);
  
end

%% %%%%%%%%%%%%%%%%%%% FIT TYPE-C + TYPE-D MODELS [FITHRF_GLMDENOISE, FITHRF_GLMDENOISE_RR]

% setup
todo = [];
if opt.wantglmdenoise==1 && (opt.wantfileoutputs(3)==1 || opt.wantmemoryoutputs(3)==1)
  todo = [todo 3];  % the user wants the type-C model returned
end
if opt.wantfracridge==1 && (opt.wantfileoutputs(4)==1 || opt.wantmemoryoutputs(4)==1)
  todo = [todo 4];  % the user wants the type-D model returned
end

% process models
for ttt=1:length(todo)
  whmodel = todo(ttt);

  %% we need to do some tricky setup
  
  % if this is just a GLMdenoise case, we need to fake it
  if whmodel==3
    fracstouse = [1];    % here, we need to fake this in order to get the outputs
    fractoselectix = 1;
    autoscaletouse = 0;  % not necessary, so turn off
  end
  
  % if this is a fracridge case
  if whmodel==4
  
    % if the user specified only one fraction
    if length(opt.fracs)==1
    
      % if the first one is 1, this is easy
      if opt.fracs(1)==1
        fracstouse = [1];
        fractoselectix = 1;
        autoscaletouse = 0;  % not necessary, so turn off
 
      % if the first one is not 1, we might need 1
      else
        fracstouse = [1 opt.fracs];
        fractoselectix = 2;
        autoscaletouse = opt.wantautoscale;
      end
    
    % otherwise, we have to do costly cross-validation
    else

      % set these
      fractoselectix = NaN;
      autoscaletouse = opt.wantautoscale;
    
      % if the first one is 1, this is easy
      if opt.fracs(1)==1
        fracstouse = opt.fracs;
      
      % if the first one is not 1, we might need 1
      else
        fracstouse = [1 opt.fracs];
      end

    end
    
  end

  %% ok, proceed

  % initialize
  modelmd =     zeros(nx*ny*nz,numtrials,'single');     % X * Y * Z x trialbetas  [the final beta estimates]
  R2 =          zeros(nx,ny,nz,'single');               % X x Y x Z               [the R2 for the specific optimal frac]
  R2run =       zeros(nx*ny*nz,numruns,'single');       % X * Y * Z x runs        [the R2 separated by runs for the optimal frac]
  FRACvalue   = zeros(nx,ny,nz,'single');               % X x Y x Z               [best fraction]
  scaleoffset = zeros(nx*ny*nz,2,'single');             % X * Y * Z x 2           [scale and offset]

  % loop over chunks
  if whmodel==3
    fprintf('*** FITTING TYPE-C MODEL (GLMDENOISE) ***\n');
  else
    fprintf('*** FITTING TYPE-D MODEL (GLMDENOISE_RR) ***\n');
  end
  for z=1:length(chunks)
    fprintf('working on chunk %d of %d.\n',z,length(chunks));

    % loop over possible HRFs
    for hh=1:size(opt.hrflibrary,2)

      % figure out which voxels to process.
      % this will be a vector of indices into the small chunk that we are processing.
      % our goal is to fully process this set of voxels!
      goodix = flatten(find(HRFindex(chunks{z},:,:)==hh));
    
      % extract the data we want to process.
      data0 = cellfun(@(x) subscript(squish(x(chunks{z},:,:,:),3),{goodix ':'}),data,'UniformOutput',0);
    
      % calculate the corresponding indices relative to the full volume
      temp = zeros(size(HRFindex));
      temp(chunks{z},:,:) = 1;
      relix = subscript(find(temp),goodix);

      % process each frac
      clear results0;
      for ll=1:length(fracstouse)

        % define options
        optA = struct('maxpolydeg',opt.maxpolydeg, ...
                      'wantpercentbold',0, ...
                      'suppressoutput',1, ...
                      'frac',fracstouse(ll));
        optA.extraregressors = cell(1,length(data0));
        if pcnum > 0
          for rr=1:length(data0)
            optA.extraregressors{rr} = cat(2,optA.extraregressors{rr},pcregressors{rr}(:,1:pcnum));
          end
        end

        % fit the entire dataset using the specific frac
        [results0(ll),cache] = GLMestimatemodel(designSINGLE,data0, ...
                                 stimdur,tr,'assume',opt.hrflibrary(:,hh),0,optA);
      
        % save some memory
        results0(ll).models = [];
        results0(ll).modelse = [];
    
      end
      
      % perform cross-validation if necessary
      if isnan(fractoselectix)
        
        % this is the weird special case where we have to ignore the artificially added 1
        if opt.fracs(1) ~= 1
          badness = calcbadness(opt.xvalscheme,validcolumns,stimix,results0(2:end));
          [~,FRACindex0] = min(badness,[],2);
          FRACindex0 = FRACindex0 + 1;
        else
          badness = calcbadness(opt.xvalscheme,validcolumns,stimix,results0);  % compute the cross-validation performance values
          [~,FRACindex0] = min(badness,[],2);  % pick best frac (FRACindex0 is V x 1 with the index of the best frac)
        end

      % if we already know fractoselectix, skip the cross-validation
      else
        FRACindex0 = fractoselectix*ones(length(relix),1);
      end
    
      % prepare output
      FRACvalue(relix) = fracstouse(FRACindex0);
      for ll=1:length(fracstouse)
        ii = find(FRACindex0==ll);
      
        % scale and offset to match the unregularized result
        if autoscaletouse
          for vv=1:length(ii)
            X = [results0(ll).modelmd{2}(ii(vv),:); ones(1,numtrials)]';
            h = olsmatrix(X)*results0(1).modelmd{2}(ii(vv),:)';  % Notice the 1
            if h(1) < 0
              h = [1 0]';
            end
            scaleoffset(relix(ii(vv)),:) = h;
            modelmd(relix(ii(vv)),:) = X*h;
          end
        else
          scaleoffset = [];
          modelmd(relix(ii),:) = results0(ll).modelmd{2}(ii,:);
        end
      
        R2(relix(ii))        = results0(ll).R2(ii);
        R2run(relix(ii),:)   = results0(ll).R2run(ii,:);
      end

    end

  end

  % deal with dimensions
  modelmd = reshape(modelmd,[nx ny nz numtrials]);
  modelmd = bsxfun(@rdivide,modelmd,abs(meanvol)) * 100;  % deal with percent BOLD change
  R2run = reshape(R2run,[nx ny nz numruns]);
  if ~isempty(scaleoffset)
    scaleoffset = reshape(scaleoffset,[nx ny nz 2]);
  end
  
  % save to disk if desired
  if whmodel==3
    allvars = {'HRFindex','HRFindexrun','totalbadness','pcnum','xvaltrend','noisepool','pcregressors','modelmd','R2','R2run','meanvol'};
    file0 = fullfile(outputdir,'TYPEC_FITHRF_GLMDENOISE.mat');
  else
    allvars = {'HRFindex','HRFindexrun','totalbadness','pcnum','xvaltrend','noisepool','pcregressors','modelmd','R2','R2run','FRACvalue','scaleoffset','meanvol'};
    file0 = fullfile(outputdir,'TYPED_FITHRF_GLMDENOISE_RR.mat');
  end
  if opt.wantfileoutputs(whmodel)==1
    save(file0,allvars{:},'-v7.3');
  end

  % figures?
  if wantfig
    if opt.wantglmdenoise==1
      if is3d
        imwrite(uint8(255*makeimagestack(noisepool,[0 1])),gray(256),fullfile(outputdir,'noisepool.png'));
      end
      figureprep;
      plot(0:opt.numpcstotry,xvaltrend);
      straightline(pcnum,'v','r-');
      xlabel('Number of GLMdenoise regressors');
      ylabel('Cross-validation performance (higher is better)');
      figurewrite('xvaltrend',[],[],outputdir);
    end
    if opt.wantfracridge==1 && is3d
      imwrite(uint8(255*makeimagestack(R2,[0 100]).^0.5),hot(256),fullfile(outputdir,'typeD_R2.png'));
      imwrite(uint8(255*makeimagestack(FRACvalue,[0 1])),bone(256),fullfile(outputdir,'FRACvalue.png'));
    end
  end

  % preserve in memory if desired
  if opt.wantmemoryoutputs(whmodel)==1
    results{whmodel} = struct;
    for p=1:length(allvars)
      results{whmodel}.(allvars{p}) = eval(allvars{p});
    end
  end

end

%%%%%

function badness = calcbadness(xvals,validcolumns,stimix,results)

% function badness = calcbadness(xvals,validcolumns,stimix,results)
%
% <xvals> is a cell vector of vectors of run indices
% <validcolumns> is a cell vector, each element is the vector of trial indices associated with the run
% <stimix> is a cell vector, each element is the vector of actual condition numbers occurring with a given run
% <results> is a 1 x n with results. the first one is SPECIAL and is unregularized.

% initialize
badness = zeros(size(results(1).modelmd{2},1),length(results));  % voxels x hyperparameters with the sum of the squared error from cross-validation

% calc
alltheruns = catcell(2,xvals);

% do cross-validation
for xx=1:length(xvals)

  % calc
  testix = xvals{xx};                    % which runs are testing, e.g. [3 4]
  trainix = setdiff(alltheruns,testix);  % which runs are training, e.g. [1 2 5 6 7 8 9 10 11 12]
  
  % calc
  testcols = catcell(2,validcolumns(testix));    % vector of trial indices in the testing data
  traincols = catcell(2,validcolumns(trainix));  % vector of trial indices in the training data
  testids = catcell(2,stimix(testix));           % vector of condition-ids in the testing data
  trainids = catcell(2,stimix(trainix));         % vector of condition-ids in the training data
  
  % calculate cross-validation performance
  for ll=1:length(results)
%    hashrec = cell(1,max(testids));  % speed-up by caching results
    for ttt=1:length(testids)
      haveix = find(trainids==testids(ttt));  % which training trials match the current condition-id?
      if ~isempty(haveix)
        
        % NOTE:
        % testcols(ttt) tells us which trial in the testing runs to pull betas for (these are 1-based trial numbers)
        % traincols(haveix) tells us the corresponding trials (isolated within the training runs) to pull betas for (these are 1-based trial numbers)

%        if isempty(hashrec{testids(ttt)})
%          hashrec{testids(ttt)} = mean(results(ll).modelmd{2}(:,traincols(haveix)),2);  % voxels x 1
%          hashrec{testids(ttt)} = results(ll).modelmd{2}(:,traincols(haveix));  % voxels x instances
%        end
        badness(:,ll) = badness(:,ll) + sum((results(ll).modelmd{2}(:,traincols(haveix)) - ...
                                             repmat(results(1).modelmd{2}(:,testcols(ttt)),[1 length(haveix)])).^2,2);  % NOTICE the results(1)

      end
    end
  end

end

%%%%%%%%%%%%%%%%%%% JUNK:

  % DEPRECATED
  %
  % % visualize
  % figureprep; hold on;
  % rvals = [1 3 5 10 20 30];
  % cmap0 = jet(length(rvals));
  % for pp=1:length(rvals)
  %   temp = totalbadness(onoffR2(:)>rvals(pp),:);
  %   plot(0:opt.numpcstotry,calczscore(median(temp,1)),'-','Color',cmap0(pp,:));
  % end
  % straightline(pcnum,'v','k-');
  % xlabel('number of pcs');
  % ylabel('median badness, z-scored');
  % figurewrite('checkbadness',[],[],outputtempdir);
  % 
  % % visualize  [PERHAPS GO BACK TO LINEAR; USE SCATTERSPARSE?]
  % rvals = [1 5 20];
  % colors = {'r' 'g' 'b'};
  % for p=1:opt.numpcstotry
  %   figureprep([100 100 900 900]);
  %   for cc=1:length(rvals)
  %     temp = totalbadness(onoffR2(:)>rvals(cc),:);
  %     scatter(log(temp(:,1)),log(temp(:,1+p)),[colors{cc} '.']);
  %   end
  %   axissquarify;
  %   %ax = axis;
  %   %axis([0 ax(2) 0 ax(2)]);
  %   xlabel('log error for no pcs');
  %   ylabel(sprintf('log error for %d pcs',p));
  %   figurewrite(sprintf('scatter%02d',p),[],[],outputtempdir);
  % end
