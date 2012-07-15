$ = jQuery.sub()

class App.Navigation extends App.Controller
  constructor: ->
    super
    @log 'nav...'
    @render()
    
    sync_ticket_overview = =>
      @interval( @ticket_overview, 30000, 'nav_ticket_overview' )

    sync_recent_viewed = =>
      @interval( @recent_viewed, 40000, 'nav_recent_viewed' )
    
    Spine.bind 'navupdate', (data) =>
      @update(arguments[0])
    
    Spine.bind 'navrebuild', (user) =>
      @log 'navbarrebuild', user
      @render(user)

    Spine.bind 'navupdate_remote', (user) =>
      @log 'navupdate_remote'
      @delay( sync_ticket_overview, 500 )
      @delay( sync_recent_viewed, 1000 )
    
    # rerender if new overview data is there
    @delay( sync_ticket_overview, 800 )
    @delay( sync_recent_viewed, 1000 )
    
  render: (user) ->
    nav_left  = @getItems( navbar: Config.NavBar )
    nav_right = @getItems( navbar: Config.NavBarRight )

    @html App.view('navigation')(
      navbar_left:  nav_left,
      navbar_right: nav_right,
      user:         user,
    )

  getItems: (data) ->
    navbar =  _.values(data.navbar)
    
    level1 = []
    dropdown = {}

    for item in navbar
      if typeof item.callback is 'function'
        data = item.callback() || {}
        for key, value of data
          item[key] = value
      if !item.parent
        match = 0
        if !window.Session['roles']
          match = _.include(item.role, 'Anybody')
        if window.Session['roles']
          window.Session['roles'].forEach( (role) =>
            if !match
              match = _.include(item.role, role.name)
          )
          
        if match
          level1.push item
            
    for item in navbar
      if item.parent && !dropdown[ item.parent ]
        dropdown[ item.parent ] = []

        # find all childs and order
        for itemSub in navbar
          if itemSub.parent is item.parent
            match = 0
            if !window.Session['roles']
              match = _.include(itemSub.role, 'Anybody')
            if window.Session['roles']
              window.Session['roles'].forEach( (role) =>
                if !match
                  match = _.include(itemSub.role, role.name)
              )
              
            if match
              dropdown[ item.parent ].push itemSub

        # find parent
        for itemLevel1 in level1
          if itemLevel1.target is item.parent
            sub = @getOrder(dropdown[ item.parent ])
            itemLevel1.child = sub
            
    nav = @getOrder(level1)
    return nav

  getOrder: (data) ->
    newlist = {}
    for item in data
      # check if same prio already exists
      @addPrioCount newlist, item

      newlist[ item['prio'] ] = item;

    # get keys for sort order    
    keys = _.keys(newlist)
    inorder = keys.sort(@sortit)

    # create new array with prio sort order
    inordervalue = []
    for num in inorder
      inordervalue.push newlist[ num ]
    return inordervalue
  
  sortit: (a,b) ->  
    return(a-b)
    
  addPrioCount: (newlist, item) ->
     if newlist[ item['prio'] ]
        item['prio']++
        if newlist[ item['prio'] ]
          @addPrioCount newlist, item
    
  update: (url) =>
    @el.find('li').removeClass('active')
#    if url isnt '#'
    @el.find("[href=\"#{url}\"]").parents('li').addClass('active')
#      @el.find("[href*=\"#{url}\"]").parents('li').addClass('active')

  # get data
  ticket_overview: =>

    # do no load and rerender if sub-menu is open
    open = @el.find('.open').val()
    if open isnt undefined
      return
    
    # do no load and rerender if user is not logged in
    if !window.Session['id']
      return

    # only of lod request is already done

    if !@req_overview
      @req_overview = App.Com.ajax(
        id:    'navbar_ticket_overviews',
        type:  'GET',
        url:   '/ticket_overviews',
        data:  {},
        processData: true,
        success: (data, status, xhr) =>
  
          # remove old views
          for key of Config.NavBar
            if Config.NavBar[key].parent is '#ticket/view'
              delete Config.NavBar[key]
  
          # add new views
          for item in data
            Config.NavBar['TicketOverview' + item.url] = {
              prio:   item.prio,
              parent: '#ticket/view',
              name:   item.name,
              count:  item.count,
              target: '#ticket/view/' + item.url,
              role:   ['Agent'],
            }
  
          # rebuild navbar
          Spine.trigger 'navrebuild', window.Session

          # reset ajax call
          @req_overview = undefined
      )

  # get data
  recent_viewed: =>

    # do no load and rerender if sub-menu is open
    open = @el.find('.open').val()
    if open isnt undefined
      return
    
    # do no load and rerender if user is not logged in
    if !window.Session['id']
      return

    # only of lod request is already done
    if !@req_recent_viewed
      @req_recent_viewed = App.Com.ajax(
        id:    'navbar_recent_viewed',
        type:  'GET',
        url:   '/recent_viewed',
        data:  {
          limit: 5,
        }
        processData: true,
        success: (data, status, xhr) =>
  
          items = data.recent_viewed
  
          # load user collection
          @loadCollection( type: 'User', data: data.users )
  
          # load ticket collection
          @loadCollection( type: 'Ticket', data: data.tickets )
  
          # remove old views
          for key of Config.NavBarRight
            if Config.NavBarRight[key].parent is '#current_user'
              part = Config.NavBarRight[key].target.split '::'
              if part is 'RecendViewed'
                delete Config.NavBarRight[key]
  
          # add new views
          prio = 5000
          for item in items
            divider   = false
            navheader = false
            if prio is 5000
              divider   = true
              navheader = 'Recent Viewed'
            ticket = App.Ticket.find(item.o_id)
            prio++
            Config.NavBarRight['RecendViewed::' + ticket.id] = {
              prio:      prio,
              parent:    '#current_user',
              name:      item.history_object.name + ' (' + ticket.title + ')',
              target:    '#ticket/zoom/' + ticket.id,
              role:      ['Agent'],
              divider:   divider,
              navheader: navheader
            }
  
          # rebuild navbar
          Spine.trigger 'navrebuild', window.Session

          # reset ajax call
          @req_recent_viewed = undefined
      )
