class Thorax.Views.PatientBuilder extends Thorax.View

  template: JST['patient_builder/patient_builder']

  options:
    serialize: { children: false }
    populate: { context: true, children: false }

  initialize: ->
    # FIXME need to deeply clone source data criteria to avoid editing in place; this is only a shallow clone
    @sourceDataCriteria = @model.get('source_data_criteria').clone()
    @editCriteriaCollectionView = new Thorax.CollectionView
      collection: @sourceDataCriteria
      itemView: (item) => new Thorax.Views.EditCriteriaView(model: item.model, measure: @measure)
    @expectedValuesView = new Thorax.Views.ExpectedValuesView
      model: @model
      measure: @measure
      edit: true
      values: _.extend({}, @model.get('expected_values'))

  dataCriteriaCategories: ->
    categories = {}
    @measure?.get('source_data_criteria').each (criteria) ->
      categories[criteria.get('type')] ||= new Thorax.Collection
      categories[criteria.get('type')].add criteria unless categories[criteria.get('type')].any (c) -> c.get('title') == criteria.get('title')
    categories

  events:
    'submit form': 'save'
    rendered: ->
      @$('.draggable').draggable revert: 'invalid', helper: 'clone', zIndex: 10
      @$('.droppable').droppable accept: '.ui-draggable'
      # TODO move event handling up into events object, if possible
      @$('.droppable').on 'drop', _.bind(@drop, this)
    model:
      request: (model) -> @$('input[type="submit"]').button('saving').attr(disabled: 'disabled')
      sync: (model) ->
        @patients.add model # make sure that the patient exist in the global patient collection
        bonnie.navigate 'patients', trigger: true # FIXME: figure out correct action here
    serialize: (attr) ->
      attr.birthdate = moment(attr.birthdate, 'L LT').format('X') if attr.birthdate

  # When we create the form and populate it, we want to convert some values to those appropriate for the form
  context: ->
    _(super).extend
      birthdate: moment(@model.get('birthdate'), 'X').format('L LT') if @model.get('birthdate')
      expired: @model.get('expired')?.toString()

  drop: (e, ui) ->
    measureDataCriteria = $(ui.draggable).model()
    @sourceDataCriteria.add measureDataCriteria.toPatientDataCriteria()

  save: (e) ->
    e.preventDefault()
    # Serialize the main view and the child collection views separately
    @serialize(children: false)
    childView.serialize() for cid, childView of @editCriteriaCollectionView.children
    @expectedValuesView.serialize(children: false)
    @model.save(source_data_criteria: @sourceDataCriteria)


# FIXME: When we get coffeescript scoping working again, don't need to put this in Thorax.Views scope
class Thorax.Views.EditCriteriaView extends Thorax.View

  template: JST['patient_builder/edit_criteria']

  options:
    serialize: { children: false }
    populate: { context: true, children: false }

  initialize: ->
    @editValueCollectionView = new Thorax.CollectionView
      collection: @model.get('value')
      itemView: (item) => new Thorax.Views.EditCriteriaValueView(model: item.model, measure: @measure, fieldValue: false)
    @editFieldValueCollectionView = new Thorax.CollectionView
      collection: @model.get('field_values')
      itemView: (item) => new Thorax.Views.EditCriteriaValueView(model: item.model, measure: @measure, fieldValue: true)

  serialize: ->
    childView.serialize() for cid, childView of @editValueCollectionView.children
    childView.serialize() for cid, childView of @editFieldValueCollectionView.children
    super(children: false)

  # When we create the form and populate it, we want to convert times to moment-formatted dates
  context: ->
    _(super).extend
      start_date: moment(@model.get('start_date')).format('L LT') if @model.get('start_date')
      end_date: moment(@model.get('end_date')).format('L LT') if @model.get('end_date')

  # When we serialize the form, we want to convert formatted dates back to times
  events:
    serialize: (attr) ->
      attr.start_date = moment(attr.start_date, 'L LT').format('X') * 1000 if attr.start_date
      attr.end_date = moment(attr.end_date, 'L LT').format('X') * 1000 if attr.end_date

  toggleDetails: (e) ->
    e.preventDefault()
    @$('.details').toggle()

  removeCriteria: (e) ->
    e.preventDefault()
    @model.destroy()

  newScalarValue: (e) ->
    e.preventDefault()
    @model.get('value').add type: 'PQ'

  newCodedValue: (e) ->
    e.preventDefault()
    @model.get('value').add type: 'CD'

  newScalarFieldValue: (e) ->
    e.preventDefault()
    @model.get('field_values').add type: 'PQ'

  newCodedFieldValue: (e) ->
    e.preventDefault()
    @model.get('field_values').add type: 'CD'

  newTimeFieldValue: (e) ->
    e.preventDefault()
    @model.get('field_values').add type: 'TS'


class Thorax.Views.EditCriteriaValueView extends Thorax.View

  template: JST['patient_builder/edit_value']

  context: ->
    _(super).extend
      typePQ: @model.get('type') is 'PQ'
      typeCD: @model.get('type') is 'CD'
      typeTS: @model.get('type') is 'TS'
      codes: @measure.get('value_sets').map (vs) -> vs.toJSON()
      fields: Thorax.Models.Measure.logicFields

  # When we serialize the form, we want to put the description for any CD codes into the submission
  events:
    serialize: (attr) ->
      attr.title = @measure.get('value_sets').findWhere(oid: attr.code_list_id)?.get('display_name')

  removeValue: (e) ->
    e.preventDefault()
    @model.destroy()

class Thorax.Views.ExpectedValuesView extends Thorax.View
  
  template: JST['patient_builder/expected_values']
  
  # FIXME: Needs re-writing for elegance
  initialize: ->
    @populations = @measure.get('populations')
    @popCriteria = @measure.get('population_criteria')
    if not @values? or _.size(@values) is 0
      # if the patient has no expected values, create them
      @values = {}
      evs = @values
      pc = @popCriteria
      @populations.each (p) ->
        pevHash = {}
        for key in (pop for pop in Object.keys(pc) when p.has(pop))
          pevHash[key] = 0
        evs[p.get('sub_id')] = pevHash

  measureTitle: -> " for #{@measure.get('title') ? ''}"

  # When we serialize the form, we want to update the expected_values hash
  events:
    serialize: (attr) ->
      # get all the checkboxes: $('.expected-value-tab > div > .expected-values > form > .checkbox > label > input')
      # get checkbox by id: $('.expected-value-tab > div > .expected-values > form > .checkbox > label > #DENEX')
      parsedValues = {}
      # attr.expected_values = _.extend({}, @values)
      pc = @popCriteria
      @populations.each (p) ->
        pevHash = {}
        for key in (pop for pop in Object.keys(pc) when p.has(pop))
        # selections = @$("##{p.get('sub_id')} > div > .expected-values > form > .checkbox > label > input")
          # console.log @$("##{p.get('sub_id')} > div > .expected-values > form > .checkbox > label > ##{key}")
          checkedValue = @$("##{p.get('sub_id')} > div > .expected-values > form > .checkbox > label > ##{key}").prop('checked')
          if checkedValue is true then pevHash[key] = 1 else pevHash[key] = 0
          console.log checkedValue
        parsedValues[p.get('sub_id')] = pevHash
      console.log parsedValues
      attr.expected_values = _.extend({}, parsedValues)

class Thorax.Views.ExpectedValueView extends Thorax.View
  
  template: JST['patient_builder/expected_value']
  # currently supported ev values are 0/1 for unchecked/checked
  evStatus:
    '0': ['unchecked', 'danger', 1]
    '1': ['check', 'success', 0]

  initialize: ->
    c = @criteria
    p = @population
    @currentCriteria = (pop for pop in Object.keys(c) when pop in Object.keys(p))

  events: ->
    'rendered': 'setValues'

  setValues: ->
    for c in @currentCriteria
      if @modelValues[@population.sub_id][c] is 1
        @$('#' + c).prop('checked', true)
      if @editFlag is false
        @$('#' + c).prop('disabled', true)
