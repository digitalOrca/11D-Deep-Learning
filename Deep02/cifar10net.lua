require 'nn'
require 'dp'
require 'torch'
require 'paths'
require 'optim'

--[[Layer size parameter]]


--[[Layer definition]]
net = nn.Sequential()
	V1 = nn.SpatialConvolution(3,6,5,5)
	V2 = nn.ReLU()
	V3 = nn.SpatialMaxPooling(2,2,2,2)
	V4 = nn.SpatialConvolution(6,16,5,5)
	V5 = nn.ReLU()
	V6 = nn.SpatialMaxPooling(2,2,2,2)
	V7 = nn.View(16*5*5)
	V8 = nn.Linear(16*5*5, 120)
	V9 = nn.ReLU()
	V10 = nn.Linear(120,84)
	V11 = nn.ReLU()
	V12 = nn.Linear(84,10)
	V13 = nn.LogSoftMax()
net:add(V1)
net:add(V2)
net:add(V3)
net:add(V4)
net:add(V5)
net:add(V6)
net:add(V7)
net:add(V8)
net:add(V9)
net:add(V10)
net:add(V11)
net:add(V12)
net:add(V13)

--Load Trained Network
net = torch.load("gitTorch/Deep02/Run1/trained.net")

print('Network Structure: \n' .. net:__tostring());

classes = {'airplane', 'automobile', 'bird', 'cat', 'deer',
			'dog', 'frog', 'horse', 'ship', 'truck'}

-- load training data
trainset = {
   data = torch.Tensor(50000, 3, 32, 32),
   label = torch.Tensor(50000)
}

for i=0,4 do
	batch = torch.load('gitTorch/Dataset/cifar-10-batches-t7/data_batch_'..(i+1)..'.t7','ascii')
	trainset.data[{ {i*10000+1, (i+1)*10000} }]=batch.data:t()
	trainset.label[{ {i*10000+1, (i+1)*10000} }]=batch.labels
end
trainset.label = trainset.label + 1;


--load test data
testset = {
	data = torch.Tensor(10000, 3, 32, 32),
	label = torch.Tensor(10000)
}

batch = torch.load('gitTorch/Dataset/cifar-10-batches-t7/test_batch.t7', 'ascii')
	testset.data[{ {1, 10000} }]=batch.data:t()
	testset.label[{ {1, 10000} }]=batch.labels + 1

trainset.data = trainset.data:double()	--convert data from a ByteTensor to a DoubleTensor

function trainset:size()
	return self.data:size(1)
end

--[[Normalize Training Data]]
mean = {}	--store the mean, to normalize the test set
stdv = {}	--store the standard-deviation
for i=1,3 do
	--[{image index},{channel},{vertical pixel},{horizontal pixel}]
	mean[i] = trainset.data[{ {}, {i}, {}, {} }]:mean()	--mean of each channel
	trainset.data[{ {}, {i}, {}, {} }]:add(-mean[i])	--zero out the mean

	stdv[i] = trainset.data[{ {}, {i}, {}, {} }]:std()	--std for each channel
	trainset.data[{ {}, {i}, {}, {} }]:div(stdv[i])	--scale for std
end

--[[Normalize Test Data W/ Mean and STD of Training Data]]
testset.data = testset.data:double()
for i=1,3 do
	testset.data[{ {}, {i}, {}, {}}]:add(-mean[i])
	testset.data[{ {}, {i}, {}, {}}]:div(stdv[i])
end

--[[Define Loss Function]]
criterion = nn.ClassNLLCriterion()	-- a negative log-likelihood criterion for multi-class classification

--[[Train the Network]]
optim_params = { learningRate = 0.001, momentum = 0.5, coefL1=0, coefL2=0.001, maxIteration=100}
-- retrieve parameters and gradients
parameters,gradParameters = net:getParameters()


print('Network size: \n')
print(#parameters)
--[[62006]]

-- this matrix records the current confusion across classes
confusion = optim.ConfusionMatrix(classes)
-- log results to files
trainLogger = optim.Logger(paths.concat('/home/lakechen/gitTorch/Deep02', 'train.log'))
testLogger = optim.Logger(paths.concat('/home/lakechen/gitTorch/Deep02', 'test.log'))
-- get training data size
sampleSize = (#trainset.data)[1]
-- get total training data size
trainSize = (optim_params.maxIteration)*sampleSize

--[[Start Training]]-----------------------------------------------------------------------
for epoch = 1,optim_params.maxIteration do

	 -- initialize time
   local time = sys.clock()

	for i = 1, sampleSize do	--Iterate through the entire set

		--display the progress
		xlua.progress((epoch-1)*sampleSize+i,trainSize)

		--[[Run the optimizer]]
		--define inputs and labels
		input = trainset.data[i]
		target = trainset.label[i]

		local func = function(x)

			-- get new parameters
			if x ~= parameters then
	            parameters:copy(x)
	      end
	
			-- reset gradients
	      gradParameters:zero()
	
			-- evaluate function
	      local output = net:forward(input)
	      local f = criterion:forward(output, target)
			
			 -- estimate df/dW
	       local df_do = criterion:backward(output, target)
	       net:backward(input, df_do)
			
			-- penalties (L1 and L2):
	      if optim_params.coefL1 ~= 0 or optim_params.coefL2 ~= 0 then
	         -- locals:
	         local norm,sign= torch.norm,torch.sign
	
	         -- Loss:
	         f = f + optim_params.coefL1 * norm(parameters,1)
	         f = f + optim_params.coefL2 * norm(parameters,2)^2/2
	
	         -- gradients:
	         gradParameters:add( sign(parameters):mul(optim_params.coefL1) + parameters:clone():mul(optim_params.coefL2) )
	      end

	      -- update confusion
   	   confusion:add(output, target)
		
			return f,gradParameters
		end
		optim.sgd(func, parameters, optim_params)
	end

	--Output confusion matrix
	print(confusion)
	trainLogger:add{['% mean class accuracy (train set)'] = confusion.totalValid * 100}
   confusion:zero()

	-- time taken
   time = sys.clock() - time
   time = time / sampleSize
   print("<trainer> time to learn 1 sample = " .. (time*1000) .. 'ms')
	
	-- save/log current net
   local filename = paths.concat('/home/lakechen/gitTorch/Deep02', 'trained.net')
   os.execute('mkdir -p ' .. sys.dirname(filename))
   if paths.filep(filename) then
      os.execute('mv ' .. filename .. ' ' .. filename .. '.old')
   end
   print('<trainer> saving network to '..filename)
	torch.save(filename, net)

	--next epoch
	epoch = epoch + 1

	--[[Test Network Accuracy]]
	correct = 0
	for i=1,10000 do
		local groundtruth = testset.label[i]
		local prediction = net:forward(testset.data[i])
   	local confidences, indices = torch.sort(prediction, true)
		if groundtruth == indices[1] then
			correct = correct + 1
		end
	end
	print('Network accuracy: '..(100*correct/10000)..' %')
	
	--Output confusion matrix
	testLogger:add{['% mean class accuracy (test set)'] = (100*correct/10000)}

	--Plot progress
	trainLogger:style{['% mean class accuracy (train set)'] = '-'}
	testLogger:style{['% mean class accuracy (test set)'] = '-'}
	trainLogger:plot()
	testLogger:plot()
	
end
--[[End Training]]-----------------------------------------------------------------------

--[[Native Training Method]]
--trainer = nn.StochasticGradient(net, criterion)
--trainer.learningRate = 0.001
--trainer.maxIteration = 50	--number of epochs of training
--trainer:train(trainset)



