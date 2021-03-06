functions = require('./functions').functions
utils = require('tztime').utils
OLAPCube = require('./OLAPCube').OLAPCube

class Classifier
  ###
  @class Classifier

  __Base class for all Classifiers__

  See individual subclasses for usage details
  ###

  @getBucketCountMinMax: (values) ->
    targetBucketCount = Math.floor(Math.sqrt(values.length)) + 1
    if targetBucketCount < 3
      throw new Error("Need more training data")
    min = functions.min(values)  # !TODO: Optimize this for a single loop
    max = functions.max(values)
    return {targetBucketCount, min, max}

  @generateConstantWidthBucketer: (values) ->
    {targetBucketCount, min, max} = Classifier.getBucketCountMinMax(values)
    bucketSize = (max - min) / targetBucketCount
    bucketer = []  # each row is {startOn, endBelow} meaning bucket  startOn <= x < endBelow
    bucketer.push({value: 'B' + 0, startOn: null, endBelow: min + bucketSize})
    for i in [1..targetBucketCount - 2]
      bucketer.push({value: 'B' + i, startOn: min + bucketSize * i, endBelow: min + bucketSize * (i + 1)})
    bucketer.push({value: 'B' + (targetBucketCount - 1), startOn: min + bucketSize * (targetBucketCount - 1), endBelow: null})
    return bucketer

  @generateConstantQuantityBucketer: (values) ->
    {targetBucketCount, min, max} = Classifier.getBucketCountMinMax(values)
    bucketSize = 100 / targetBucketCount
    bucketer = []  # each row is {startOn, endBelow} meaning bucket  startOn <= x < endBelow
    currentBoundary = functions.percentileCreator(bucketSize)(values)
    bucketer.push({value: 'B' + 0, startOn: null, endBelow: currentBoundary})
    for i in [1..targetBucketCount - 2]
      lastBoundary = currentBoundary
      currentBoundary = functions.percentileCreator(bucketSize * (i + 1))(values)
      bucketer.push({value: 'B' + i, startOn: lastBoundary, endBelow: currentBoundary})
    bucketer.push({value: 'B' + (targetBucketCount - 1), startOn: currentBoundary, endBelow: null})
    return bucketer

  @splitAt: (values, index) ->
    left = values.slice(0, index)
    right = values.slice(index)
    return {left, right}

  @splitAtValue: (values, split) ->
    left = []
    right = []
    for value in values
      if value < split
        left.push(value)
      else
        right.push(value)
    return {left, right}

  @optimalSplitFor2Buckets: (values) ->
    bestIndex = 1  # splitting at index 1 means that the split occurs just before the second element in the array. Interpolate for the numeric boundary.
    bestTotalErrorSquared = Number.MAX_VALUE
    for i in [1..values.length - 1]
      {left, right} = Classifier.splitAt(values, i)
      totalErrorSquared = functions.errorSquared(left) + functions.errorSquared(right)
      if totalErrorSquared < bestTotalErrorSquared
        bestTotalErrorSquared = totalErrorSquared
        bestIndex = i
        bestLeft = left
        bestRight = right
    splitAt = (values[bestIndex - 1] + values[bestIndex]) / 2
    return {splitAt, left: bestLeft, right: bestRight}

  @areAllSame: (values) ->
    firstValue = values[0]
    for value in values
      if value != firstValue
        return false
    return true

  @findBucketSplits: (currentSplits, values, targetBucketCount, originalValues) ->
    unless originalValues?
      originalValues = values.slice(0)
    if values.length < 5 or Classifier.areAllSame(values)
      return null
    {splitAt, left, right} = Classifier.optimalSplitFor2Buckets(values)
    currentSplits.push(splitAt)
    currentSplits.sort((a, b) -> return a - b)
    while currentSplits.length < targetBucketCount - 1
      # Find the bucket with the biggest error
      right = originalValues
      maxErrorSquared = 0
      maxErrorSquaredValues = null
      for split in currentSplits
        {left, right} = Classifier.splitAtValue(right, split)
        errorSquared = functions.errorSquared(left)
        if errorSquared > maxErrorSquared
          maxErrorSquared = errorSquared
          maxErrorSquaredValues = left
      errorSquared = functions.errorSquared(right)
      if errorSquared > maxErrorSquared
        maxErrorSquared = errorSquared
        maxErrorSquaredValues = right
      {splitAt, left2, right2} = Classifier.optimalSplitFor2Buckets(maxErrorSquaredValues)
      currentSplits.push(splitAt)
      currentSplits.sort((a, b) -> return a - b)
    return currentSplits

  @generateVOptimalBucketer: (values) ->  # !TODO: Split out bucketers and use with histogram when upgrading histogram
    {targetBucketCount, min, max} = Classifier.getBucketCountMinMax(values)
    values.sort((a, b) -> return a - b)
    splits = []
    Classifier.findBucketSplits(splits, values, targetBucketCount)
    splits.sort((a, b) -> return a - b)

    bucketer = []  # each row is {startOn, endBelow} meaning bucket  startOn <= x < endBelow
    currentBoundary = splits[0]
    bucketer.push({value: 'B' + 0, startOn: null, endBelow: currentBoundary})
    for i in [1..splits.length - 1]
      lastBoundary = currentBoundary
      currentBoundary = splits[i]
      bucketer.push({value: 'B' + i, startOn: lastBoundary, endBelow: currentBoundary})
    bucketer.push({value: 'B' + splits.length, startOn: currentBoundary, endBelow: null})

    return bucketer

  discreteizeRow: (row) ->  # This will replace the value with the index of the bin that matches that value
    for feature in @features
      if feature.type is 'continuous'
        value = row[feature.field]
        unless value?
          throw new Error("Could not find field #{feature.field} in #{JSON.stringify(row)}.")
        for bin, index in feature.bins
          if bin.startOn?
            if bin.endBelow?
              if bin.startOn <= value < bin.endBelow
                row[feature.field] = bin.value
                break
            else if bin.startOn <= value
              row[feature.field] = bin.value
              break
          else if value < bin.endBelow
            row[feature.field] = bin.value
            break

    return row


class BayesianClassifier extends Classifier
  ###
  @class BayesianClassifier

  __A Bayesian classifier with non-parametric modeling of distributions using v-optimal bucketing.__

  If you look for libraries for Bayesian classification, the primary use case is spam filtering and they assume that
  the presence or absence of a word is the only feature you are interested in. This is a more general purpose tool.

  ## Features ##

  * Works even for bi-modal and other non-normal distributions
  * No requirement that you identify the distribution
  * Uses [non-parametric modeling](http://en.wikipedia.org/wiki/Non-parametric_statistics)
  * Uses v-optimal bucketing so it deals well with outliers and sharp cliffs
  * Serialize (`getStateForSaving()`) and deserialize (`newFromSavedState()`) to preserve training between sessions

  ## Why the assumption of a normal distribution is bad in some cases ##

  The [wikipedia example of using Bayes](https://en.wikipedia.org/wiki/Naive_Bayes_classifier#Sex_classification) tries
  to determine if someone was male or female based upon the height, weight
  and shoe size. The assumption is that men are generally larger, heavier, and have larger shoe size than women. In the
  example, they use the mean and variance of the male-only and female-only populations to characterize those
  distributions. This works because these characteristics are generally normally distributed **and the distribution for
  men is generally to the right of the distribution for women**.

  However, let's ask a group of folks who work together if they consider themselves a team and let's try to use the size
  of the group as a feature to predict what a new group would say. If the group is very small (1-2 people), they are
  less likely to consider themselves a team (partnership maybe), but if they are too large (say > 10), they are also
  unlikely to refer to themselves as a team. The non-team distribution is bimodal, looking at its mean and variance
  completely mis-characterizes it. Also, the distribution is zero bound so it's likely to be asymmetric, which also
  poses problems for a normal distribution assumption.

  ## So what do we do instead? ##

  This classifier uses the actual values (in buckets) rather than characterize the distribution as "normal", "log-normal", etc.
  This approach is often referred to as "building a non-parametric model".

  **Pros/Cons**. The use of a non-parametric approach will allow us to deal with non-normal distributions (asymmetric,
  bimodal, etc.) without ever having to identify which nominal distribution is the best fit or having to ask the user
  (who may not know) what distribution to use. The downside to this approach is that it generally requires a larger
  training set. You will need to experiment to determine how small is too small for your situation.

  This approach is hinted at in the [wikipedia article on Bayesian classifiers](https://en.wikipedia.org/wiki/Naive_Bayes_classifier)
  as "binning to discretize the feature values, to obtain a new set of Bernoulli-distributed features". However, this
  classifier does not create new separate Bernoulli features for each bin. Rather, it creates a mapping function from a feature
  value to a probability indicating how often the feature value is coincident with a particular outputField value. This mapping
  function is different for each bin.

  ## V-optimal bucketing ##

  There are two common approaches to bucketing:

  1. Make each bucket be equal in width along the x-axis (like we would for a histogram) (equi-width)
  2. Make each bucket have roughly the same number of data points (equi-depth)

  It turns out neither of the above works out well unless the training set is relatively large. Rather, there is an
  approach called [v-optimal bucketing](http://en.wikipedia.org/wiki/V-optimal_histograms) which attempts to find the
  optimal boundaries in the data. The basic idea is to look for the splits that provide the minimum total error-squared
  where the "error" for each point is the distance of that point from the arithmetic mean. This classifier uses v-optimal
  bucketing when the training set has 144 or fewer rows. Above that it switches to equi-depth bucketing. Note, I only
  evaluated a single scenario (Rally RealTeam), but 144 was the point where equi-depth started to provide as-good results as
  v-optimal bucketing. Note, in my test, much larger sets had moderately _better_ results with equi-depth bucketing.

  That said, the 144 cutoff was determined with an older version of the v-optimal bucketing. I've since fixed that old
  algorithms tendency to produce lopsided distributions. It may very well be possible for v-optimal to be better for
  even larger numbers of data points. I need to run a new experiment to see.

  The algorithm used here for v-optimal bucketing is slightly inspired by
  [this](http://www.mathcs.emory.edu/~cheung/Courses/584-StreamDB/Syllabus/06-Histograms/v-opt3.html).
  However, I've made some different choices about when to terminate the splitting and deciding what portion to split again. To
  understand the essence of the algorithm used, you need only look at the 9 lines of code in the `findBucketSplits()` function.
  The `optimalSplitFor2Buckets()` function will split the values into two buckets. It tries each possible split
  starting with only one in the bucket on the left all the way down to a split with only one in the bucket on the right.
  It then figures out which split has the highest error and splits that again until we have the target number of splits.

  ## Simple example ##

  First we need to require the classifier.

      {BayesianClassifier} = require('../')

  Before we start, let's take a look at our training set. The assumption is that we think TeamSize and HasChildProject
  will be predictors for RealTeam.

      trainingSet = [
        {TeamSize: 5, HasChildProject: 0, RealTeam: 1},
        {TeamSize: 3, HasChildProject: 1, RealTeam: 0},
        {TeamSize: 3, HasChildProject: 1, RealTeam: 1},
        {TeamSize: 1, HasChildProject: 0, RealTeam: 0},
        {TeamSize: 2, HasChildProject: 1, RealTeam: 0},
        {TeamSize: 2, HasChildProject: 0, RealTeam: 0},
        {TeamSize: 15, HasChildProject: 1, RealTeam: 0},
        {TeamSize: 27, HasChildProject: 1, RealTeam: 0},
        {TeamSize: 13, HasChildProject: 1, RealTeam: 1},
        {TeamSize: 7, HasChildProject: 0, RealTeam: 1},
        {TeamSize: 7, HasChildProject: 0, RealTeam: 0},
        {TeamSize: 9, HasChildProject: 1, RealTeam: 1},
        {TeamSize: 6, HasChildProject: 0, RealTeam: 1},
        {TeamSize: 5, HasChildProject: 0, RealTeam: 1},
        {TeamSize: 5, HasChildProject: 0, RealTeam: 0},
      ]

  Now, let's set up a simple config indicating our assumptions. Note how the type for TeamSize is 'continuous'
  whereas the type for HasChildProject is 'discrete' eventhough a number is stored. Continuous types must be numbers
  but discrete types can either be numbers or strings.

      config =
        outputField: "RealTeam"
        features: [
          {field: 'TeamSize', type: 'continuous'},
          {field: 'HasChildProject', type: 'discrete'}
        ]

  We can now instantiate the classifier with that config,

      classifier = new BayesianClassifier(config)

  and pass in our training set.

      percentWins = classifier.train(trainingSet)

  The call to `train()` returns the percentage of times that the trained classifier gets the right answer for the training
  set. This should usually be pretty high. Anything below say, 70% and you probably don't have the right "features"
  in your training set or you don't have enough training set data. Our made up exmple is a borderline case.

      console.log(percentWins)
      # 0.7333333333333333

  Now, let's see how the trained classifier is used to predict "RealTeam"-ness. We simply pass in an object with
  fields for each of our features. A very small team with child projects are definitely not a RealTeam.

      console.log(classifier.predict({TeamSize: 1, HasChildProject: 1}))
      # 0

  However, a mid-sized project with no child projects most certainly is a RealTeam.

      console.log(classifier.predict({TeamSize: 7, HasChildProject: 0}))
      # 1

  Here is a less obvious case, with one indicator going one way (the right size) and another going the other way (has child projects).

      console.log(classifier.predict({TeamSize: 5, HasChildProject: 1}))
      # 1

  If you want to know the strength of the prediction, you can pass in `true` as the second parameter to the `predict()` method.

      console.log(classifier.predict({TeamSize: 5, HasChildProject: 1}, true))
      # { '0': 0.3786982248520709, '1': 0.6213017751479291 }

  We're only 62.1% sure this is a RealTeam. Notice how the keys for the output are strings eventhough we passed in values
  of type Number for the RealTeam field in our training set. We had no choice in this case because keys of JavaScript
  Objects must be strings. However, the classifier is smart enough to convert it back to the correct type if you call
  it without passing in true for the second parameter.

  Like the Lumenize calculators, you can save and restore the state of a trained classifier.

      savedState = classifier.getStateForSaving('some meta data')
      newClassifier = BayesianClassifier.newFromSavedState(savedState)
      console.log(newClassifier.meta)
      # some meta data

  It will make the same predictions.

      console.log(newClassifier.predict({TeamSize: 5, HasChildProject: 1}, true))
      # { '0': 0.3786982248520709, '1': 0.6213017751479291 }

  ###

  constructor: (@userConfig) ->
    ###
    @constructor
    @param {Object} userConfig See Config options for details.
    @cfg {String} outputField String indicating which field in the training set is what we are trying to predict
    @cfg {Object[]} features Array of Maps which specifies the fields to use as features. Each row in the array should
     be in the form of `{field: <fieldName>, type: <'continuous' | 'discrete'>}`. Note, that you can even declare Number type
     fields as 'discrete'. It is preferable to do this if you know that it can only be one of a hand full of values
     (0 vs 1 for example).

     **WARNING: If you choose 'discrete' for the feature type, then ALL possible values for that feature must appear
     in the training set. If the classifier is asked to make a prediction with a value that it has never seen
     before, it will fail catostrophically.**
    ###
    @config = utils.clone(@userConfig)
    @outputField = @config.outputField
    @features = @config.features


  train: (userSuppliedTrainingSet) ->
    ###
    @method train
     Train the classifier with a training set.
    @return {Number} The percentage of time that the trained classifier returns the expected outputField for the rows
     in the training set. If this is low (say below 70%), you need more predictive fields and/or more data in your
     training set.
    @param {Object[]} userSuppliedTrainingSet an Array of Maps containing a field for the outputField as well as a field
     for each of the features specified in the config.
    ###

    # make a copy of the trainingSet
    trainingSet = utils.clone(userSuppliedTrainingSet)

    # find unique values for outputField
    outputDimension = [{field: @outputField}]
    outputValuesCube = new OLAPCube({dimensions: outputDimension}, trainingSet)
    @outputValues = outputValuesCube.getDimensionValues(@outputField)
    @outputFieldTypeIsNumber = true
    for value in @outputValues
      unless utils.type(value) is 'number'
        @outputFieldTypeIsNumber = false

    # calculate base probabilities for each of the @outputValues
    n = trainingSet.length
    filter = {}
    @baseProbabilities = {}
    for outputValue in @outputValues
      filter[@outputField] = outputValue
      countForThisValue = outputValuesCube.getCell(filter)._count
      @baseProbabilities[outputValue] = countForThisValue / n

    if n >= 144
      bucketGenerator = Classifier.generateConstantQuantityBucketer
    else
      bucketGenerator = Classifier.generateVOptimalBucketer

    # calculate probabilities for each of the feature fields
    for feature in @features
      if feature.type is 'continuous'
        # create v-optimal buckets
        values = (row[feature.field] for row in trainingSet)  # !TODO: skip this section if the current feature is missing from the row
        bucketer = bucketGenerator(values)
        feature.bins = bucketer
      else if feature.type is 'discrete'
        # Right now, I don't think we need to do anything here. The continuous data has bins and the discrete data does not, but we
        # efficiently add them after we create the OLAP cube for the feature
      else
        throw new Error("Unrecognized feature type: #{feature.type}.")

    # convert the continuous data into discrete data using the just-created buckets
    @discreteizeRow(row) for row in trainingSet
    # Now the data looks like this:
    #  bins: [
    #    {value: 'B0', startOn: null, endBelow: 5.5},
    #    {value: 'B1', startOn: 5.5, endBelow: 20.25},
    #    {value: 'B2', startOn: 20.25, endBelow: null}
    #  ]

    # create probabilities for every bin/outputFieldValue combination
    for feature in @features
      dimensions = [{field: @outputField, keepTotals: true}]
      dimensions.push({field: feature.field})
      featureCube = new OLAPCube({dimensions}, trainingSet)
      featureValues = featureCube.getDimensionValues(feature.field)
      if feature.type is 'discrete'
        feature.bins = ({value} for value in featureValues)  # This is where we create the bins for discrete features
      for bin in feature.bins
        bin.probabilities = {}
        for outputValue in @outputValues
          filter = {}
          filter[feature.field] = bin.value
          denominatorCell = featureCube.getCell(filter)
          if denominatorCell?
            denominator = denominatorCell._count
          else
            denominator = 0
#            throw new Error("No values for #{feature.field}=#{bin.value} and #{@outputField}=#{outputValue}.")
          filter[@outputField] = outputValue
          numeratorCell = featureCube.getCell(filter)
          numerator = numeratorCell?._count | 0
          bin.probabilities[outputValue] = numerator / denominator

    # calculate accuracy for training set
    trainingSet = utils.clone(userSuppliedTrainingSet)  # !TODO: Upgrade to calculate off of a validation set if provided
    wins = 0
    loses = 0
    for row in trainingSet
      prediction = @predict(row)
      if prediction == row[@outputField]
        wins++
      else
        loses++
    percentWins = wins / (wins + loses)
    return percentWins

  predict: (row, returnProbabilities = false) ->
    ###
    @method predict
     Use the trained classifier to make a prediction.
    @return {String|Number|Object} If returnProbabilities is false (the default), then it will return the prediction.
     If returnProbabilities is true, then it will return an Object indicating the probability for each possible
     outputField value.
    @param {Object} row an Object containing a field for each of the features specified by the config.
    @param {Boolean} [returnProbabilities = false] If true, then the output will indicate the probabilities of each
     possible outputField value. Otherwise, the output of a call to `predict()` will return the predicted value with
     the highest probability.
    ###

    row = @discreteizeRow(row)
    probabilities = {}
    for outputValue, probability of @baseProbabilities
      probabilities[outputValue] = probability
    for feature in @features  # !TODO: Skip if row[feature.field] is null
      matchingBin = null
      for bin in feature.bins
        if row[feature.field] == bin.value
          matchingBin = bin
          break
      unless matchingBin?
        throw new Error("No matching bin for #{feature.field}=#{row[feature.field]} in the training set.")
      for outputValue, probability of probabilities
        # Bayes theorem
        probabilities[outputValue] = probability * matchingBin.probabilities[outputValue] / (probability * matchingBin.probabilities[outputValue] + (1 - probability) * (1 - matchingBin.probabilities[outputValue]))

    # Find the outputValue with the max probability
    max = 0
    outputValueForMax = null
    for outputValue, probability of probabilities
      if probability > max
        max = probability
        outputValueForMax = outputValue

    if returnProbabilities
      return probabilities
    else
      if @outputFieldTypeIsNumber
        return Number(outputValueForMax)
      else
        return outputValueForMax


  getStateForSaving: (meta) ->
    ###
    @method getStateForSaving
      Enables saving the state of a Classifier.

      See the bottom of the "Simple example" for example code of using this
      saving and restoring functionality.

    @param {Object} [meta] An optional parameter that will be added to the serialized output and added to the meta field
      within the deserialized Classifier
    @return {Object} Returns an Ojbect representing the state of the Classifier. This Object is suitable for saving to
      an object store. Use the static method `newFromSavedState()` with this Object as the parameter to reconstitute the Classifier.
    ###
    out =
      userConfig: @userConfig
      outputField: @outputField
      outputValues: @outputValues
      outputFieldTypeIsNumber: @outputFieldTypeIsNumber
      baseProbabilities: @baseProbabilities
      features: @features

    if meta?
      out.meta = meta
    return out

  @newFromSavedState: (p) ->
    ###
    @method newFromSavedState
      Deserializes a previously stringified Classifier and returns a new Classifier.

      See the bottom of the "Simple example" for example code of using this
      saving and restoring functionality.

    @static
    @param {String/Object} p A String or Object from a previously saved Classifier state
    @return {Classifier}
    ###
    if utils.type(p) is 'string'
      p = JSON.parse(p)

    classifier = new BayesianClassifier(p.userConfig)
    classifier.outputField = p.outputField
    classifier.outputValues = p.outputValues
    classifier.outputFieldTypeIsNumber = p.outputFieldTypeIsNumber
    classifier.baseProbabilities = p.baseProbabilities
    classifier.features = p.features

    if p.meta?
      classifier.meta = p.meta

    return classifier


exports.Classifier = Classifier
exports.BayesianClassifier = BayesianClassifier
