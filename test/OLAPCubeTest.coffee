OLAPCube = require('../src/OLAPCube').OLAPCube
{csvStyleArray_To_ArrayOfMaps} = require('../')
utils = require('../src/utils')

###
Test to-do
  min and max without values
  push the field down into the metrics field like derived fields
  flatten the metrics into the rows
###
exports.olapTest =

  testSimple: (test) ->
    facts = [
      {_ProjectHierarchy: [1, 2, 3], Priority: 1, Points: 10},
      {_ProjectHierarchy: [1, 2, 4], Priority: 2, Points: 5 },
      {_ProjectHierarchy: [5]      , Priority: 1, Points: 17},
      {_ProjectHierarchy: [1, 2]   , Priority: 1, Points: 3 },
    ]

    dimensions = [
      {field: "_ProjectHierarchy", type: 'hierarchy'},
      {field: "Priority"}
    ]

    metrics = [
      {field: "Points", metric: "sum"},
      {field: "Points", metric: "standardDeviation"}
    ]

    config = {dimensions, metrics}
    config.keepTotals = true

    cube = new OLAPCube(config, facts)

    expected = {
      _ProjectHierarchy: null,
      Priority: 1,
      _count: 3,
      Points_sumSquares: 398,
      Points_sum: 30,
      Points_standardDeviation: 7
    }

    test.deepEqual(expected, cube.getCell({Priority: 1}))

    expected = {
      _ProjectHierarchy: [ 1 ],
      Priority: null,
      _count: 3,
      Points_sumSquares: 134,
      Points_sum: 18,
      Points_standardDeviation: 3.605551275463989
    }
    test.deepEqual(expected, cube.getCell({_ProjectHierarchy: [1]}))

    expected = [null, [1], [1, 2], [1, 2, 3], [1, 2, 4], [5]]
    test.deepEqual(expected, cube.getDimensionValues('_ProjectHierarchy'))

    expected = [null, 1, 2]
    test.deepEqual(expected, cube.getDimensionValues('Priority'))

    expected = '''
      |        || Total |     1     2|
      |==============================|
      |Total   ||    35 |    30     5|
      |------------------------------|
      |[1]     ||    18 |    13     5|
      |[1,2]   ||    18 |    13     5|
      |[1,2,3] ||    10 |    10      |
      |[1,2,4] ||     5 |           5|
      |[5]     ||    17 |    17      |
    '''

    outString = cube.toString('_ProjectHierarchy', 'Priority', 'Points_sum')
    test.equal(expected, outString)

    test.done()

  testPossibilities: (test) ->
    test.deepEqual([null, 'a'], OLAPCube._possibilities('a', undefined, true))

    test.deepEqual([null, 7], OLAPCube._possibilities(7, undefined, true))

    test.deepEqual([null, '1', '2', '3'], OLAPCube._possibilities(['1', '2', '3'], undefined, true))  # Tags

    expected = [
      null,
      ['1', '2', '3'],
      ['1', '2'],
      ['1']
    ]
    test.deepEqual(expected, OLAPCube._possibilities(['1', '2', '3'], 'hierarchy', true))  # Hierarchy
    test.done()

  testExpandFact: (test) ->
    singleFact =
      singleValueField: 'a'
      hierarchicalField: ['1','2','3']
      field3: 7
      field4: 3

    dimensions = [
      {field: 'singleValueField'},
      {field: 'hierarchicalField', type: 'hierarchy'}
    ]

    metrics = [
      {field: 'field3', metric: 'sum'},
      {field: 'field4', metric: 'p50'}
    ]

    expected = [
      {singleValueField: 'a', hierarchicalField: ['1'], '_count': 1, '_facts': [singleFact], 'field4_values': [3], field3_sum: 7, field4_p50: 3},
      {singleValueField: 'a', hierarchicalField: ['1','2'], '_count': 1, '_facts': [singleFact], 'field4_values': [3], field3_sum: 7, field4_p50: 3},
      {singleValueField: 'a', hierarchicalField: ['1','2','3'], '_count': 1, '_facts': [singleFact], 'field4_values': [3], field3_sum: 7, field4_p50: 3},
      {singleValueField: 'a', hierarchicalField: null, '_count': 1, '_facts': [singleFact], 'field4_values': [3], field3_sum: 7, field4_p50: 3},
      {singleValueField: null, hierarchicalField: ['1'], '_count': 1, '_facts': [singleFact], 'field4_values': [3], field3_sum: 7, field4_p50: 3}
      {singleValueField: null, hierarchicalField: ['1','2'], '_count': 1, '_facts': [singleFact], 'field4_values': [3], field3_sum: 7, field4_p50: 3},
      {singleValueField: null, hierarchicalField: ['1','2','3'], '_count': 1, '_facts': [singleFact], 'field4_values': [3], field3_sum: 7, field4_p50: 3},
      {singleValueField: null, hierarchicalField: null, '_count': 1, '_facts': [singleFact], 'field4_values': [3], field3_sum: 7, field4_p50: 3}
    ]

    config = {dimensions, metrics}
    config.keepTotals = true
    config.keepFacts = true

    cube = new OLAPCube(config)
    actual = cube._expandFact(singleFact, config)
    test.deepEqual(expected, actual)

    cube.addFacts(singleFact)

    expected = [
      {singleValueField: 'a', hierarchicalField: ['1','2']},
      {singleValueField: null, hierarchicalField: ['1','2']}
    ]
    cells = cube.getCells({hierarchicalField: ['1', '2']})
    test.equal(cells.length, 2)
    test.ok(utils.filterMatch(expected[0], cells[0]))
    test.ok(utils.filterMatch(expected[1], cells[1]))

    test.done()

  testOLAPCube: (test) ->
    aCSVStyle = [
      ['f1', 'f2'         , 'f3', 'f4'],
      ['a' , ['1','2','3'], 7   , 3   ],
      ['b' , ['1','2']    , 70  , 30  ]
    ]

    facts = csvStyleArray_To_ArrayOfMaps(aCSVStyle)

    dimensions = [
      {field: 'f2', type:'hierarchy'},
      {field: 'f1'}
    ]

    metrics = [
      {field: 'f3', metric: 'sum'},
      {field: 'f4', metric: 'p50'}
    ]

    config = {dimensions, metrics}
    config.keepTotals = true

    expectedSum = '''
      |              || Total |   "a"   "b"|
      |====================================|
      |Total         ||    77 |     7    70|
      |------------------------------------|
      |["1"]         ||    77 |     7    70|
      |["1","2"]     ||    77 |     7    70|
      |["1","2","3"] ||     7 |     7      |
    '''

    cube = new OLAPCube(config, facts)

    test.deepEqual(expectedSum, cube.toString(undefined, undefined, 'f3_sum'))

    expected = undefined
    test.deepEqual(expected, cube.getCell({f1: "z"}))

    test.done()

  testGroupBy: (test) ->
    aCSVStyle = [
      ['field1', 'field3',],
      ['a'     , 3        ],
      ['b'     , 30       ],
      ['c'     , 40       ],
      ['b'     , 4        ],
      ['b'     , 7        ],
      ['b'     , 13       ],
      ['b'     , 15       ],
      ['c'     , 17       ],
      ['b'     , 22       ],
      ['b'     , 2        ]
    ]

    facts = csvStyleArray_To_ArrayOfMaps(aCSVStyle)

    dimensions = [
      {field: 'field1'}
    ]

    metrics = [
      {field: 'field3', metric: 'sum'}
    ]

    config = {dimensions, metrics}

    cube = new OLAPCube(config, facts)

    expected = [
      {"field1": "a", "field3_sum": 3, "_count": 1},
      {"field1": "b", "field3_sum": 93, "_count": 7},
      {"field1": "c", "field3_sum": 57, "_count": 2}
    ]

    test.deepEqual(expected, cube.getCells())

    config.keepTotals = true

    cube = new OLAPCube(config, facts)

    expected = [
      {"field1": "a", "field3_sum": 3, "_count": 1},
      {"field1": null, "field3_sum": 153, "_count": 10},
      {"field1": "b", "field3_sum": 93, "_count": 7},
      {"field1": "c", "field3_sum": 57, "_count": 2}
    ]

    test.deepEqual(expected, cube.getCells())

    cube.addFacts({field1:'c', field3:10})

    expected = [
      {"field1": "a", "field3_sum": 3 , "_count": 1},
      {"field1": null, "field3_sum": 163 , "_count": 11},
      {"field1": "b", "field3_sum": 93, "_count": 7},
      {"field1": "c", "field3_sum": 67, "_count": 3}
    ]

    test.deepEqual(expected, cube.cells)

    cube.addFacts([
      {field1:'b', field3:100},
      {field1:'b', field3:200},
      {field1:'a', field3:500}
    ])

    expected = [
      {"field1": "a", "field3_sum": 503 , "_count": 2},
      {"field1": null, "field3_sum": 963 , "_count": 14},
      {"field1": "b", "field3_sum": 393, "_count": 9},
      {"field1": "c", "field3_sum": 67, "_count": 3}
    ]

    test.deepEqual(expected, cube.cells)

    test.done()

  testSaveAndRestore: (test) ->
    facts = [
      {ProjectHierarchy: [1, 2, 3], Priority: 1},
      {ProjectHierarchy: [1, 2, 4], Priority: 2},
      {ProjectHierarchy: [5]      , Priority: 1},
      {ProjectHierarchy: [1, 2]   , Priority: 1},
    ]

    dimensions = [
      {field: "ProjectHierarchy", type: 'hierarchy'},
      {field: "Priority"}
    ]

    config = {dimensions}
    config.keepTotals = true

    originalCube = new OLAPCube(config, facts)

    console.log(originalCube.config.metrics)

    dateString = '2012-12-27T12:34:56.789Z'
    savedState = originalCube.getStateForSaving({upToDate: dateString})
#    savedState = JSON.stringify(savedState)
    restoredCube = OLAPCube.newFromSavedState(savedState)
#
#    newFacts = [
#      {ProjectHierarchy: [5], Priority: 3},
#      {ProjectHierarchy: [1, 2, 4], Priority: 1}
#    ]
#    originalCube.addFacts(newFacts)
#    restoredCube.addFacts(newFacts)
#
#    test.equal(restoredCube.toString(), originalCube.toString())
#
#    test.equal(dateString, restoredCube.meta.upToDate)

    test.done()

  testLastValueMinMax: (test) ->
    facts = [
      {ProjectHierarchy: [1, 2, 3], Priority: 1},
      {ProjectHierarchy: [1, 2, 4], Priority: 2},
      {ProjectHierarchy: [5]      , Priority: 3},
      {ProjectHierarchy: [1, 2]   , Priority: 4},
    ]

    dimensions = [
      {field: "ProjectHierarchy", type: 'hierarchy'}
    ]

    metrics = [
      {field: 'Priority', metric: 'lastValue'},
      {field: 'Priority', metric: 'min'},
      {field: 'Priority', metric: 'max'}
    ]

    config = {dimensions, metrics}

    cube = new OLAPCube(config, facts)

    newFacts = [
      {ProjectHierarchy: [5], Priority: 7},
      {ProjectHierarchy: [1, 2, 4], Priority: 8}
    ]

    cube.addFacts(newFacts)

    test.equal(cube.getCell({ProjectHierarchy: [1]}).Priority_lastValue, 8)
    test.equal(cube.getCell({ProjectHierarchy: [1, 2, 3]}).Priority_lastValue, 1)
    test.equal(cube.getCell({ProjectHierarchy: [5]}).Priority_lastValue, 7)

    cell = cube.getCell({ProjectHierarchy: [5]})
    test.equal(cell.Priority_min, 3)
    test.equal(cell.Priority_max, 7)

    test.done()