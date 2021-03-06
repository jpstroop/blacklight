require 'deprecation'
module Blacklight::UrlHelperBehavior
  extend Deprecation
  self.deprecation_horizon = 'blacklight 6.0'

  ##
  # Extension point for downstream applications
  # to provide more interesting routing to
  # documents
  def url_for_document doc
    if respond_to?(:blacklight_config) and
        blacklight_config.show.route and
        (!doc.respond_to?(:to_model) or doc.to_model.is_a? SolrDocument)
      route = blacklight_config.show.route.merge(action: :show, id: doc)
      route[:controller] = controller_name if route[:controller] == :current
      route
    else
      doc
    end
  end

  # link_to_document(doc, :label=>'VIEW', :counter => 3)
  # Use the catalog_path RESTful route to create a link to the show page for a specific item.
  # catalog_path accepts a HashWithIndifferentAccess object. The solr query params are stored in the session,
  # so we only need the +counter+ param here. We also need to know if we are viewing to document as part of search results.
  def link_to_document(doc, opts={:label=>nil, :counter => nil})
    opts[:label] ||= document_show_link_field(doc)
    label = render_document_index_label doc, opts
    link_to label, url_for_document(doc), document_link_params(doc, opts)
  end

  def document_link_params(doc, opts)
    session_tracking_params(doc, opts[:counter]).deep_merge(opts.except(:label, :counter))
  end
  protected :document_link_params

  ##
  # Link to the previous document in the current search context
  def link_to_previous_document(previous_document)
    link_opts = session_tracking_params(previous_document, search_session['counter'].to_i - 1).merge(:class => "previous", :rel => 'prev')
    link_to_unless previous_document.nil?, raw(t('views.pagination.previous')), url_for_document(previous_document), link_opts do
      content_tag :span, raw(t('views.pagination.previous')), :class => 'previous'
    end
  end

  ##
  # Link to the next document in the current search context
  def link_to_next_document(next_document)
    link_opts = session_tracking_params(next_document, search_session['counter'].to_i + 1).merge(:class => "next", :rel => 'next')
    link_to_unless next_document.nil?, raw(t('views.pagination.next')), url_for_document(next_document), link_opts do
      content_tag :span, raw(t('views.pagination.next')), :class => 'next'
    end
  end

  ##
  # Current search context parameters
  def search_session_params counter 
    { :'data-counter' => counter, :'data-search_id' => current_search_session.try(:id) }
  end
  deprecation_deprecate :search_session_params

  ##
  # Attributes for a link that gives a URL we can use to track clicks for the current search session
  # @param [SolrDocument] document
  # @param [Integer] counter
  # @example
  #   session_tracking_params(SolrDocument.new(id: 123), 7)
  #   => { data: { :'tracker-href' => '/catalog/123/track?counter=7&search_id=999' } }
  def session_tracking_params document, counter
    if document.nil?
      return {}
    end
  
    { :data => {:'context-href' => track_solr_document_path(document, per_page: params.fetch(:per_page, search_session['per_page']), counter: counter, search_id: current_search_session.try(:id))}}
  end
  protected :session_tracking_params
  

  #
  # link based helpers ->
  #

  # create link to query (e.g. spelling suggestion)
  def link_to_query(query)
    p = params.except(:page, :action)
    p[:q]=query
    link_url = search_action_path(p)
    link_to(query, link_url)
  end

  ##
  # Get the path to the search action with any parameters (e.g. view type)
  # that should be persisted across search sessions.
  def start_over_path query_params = params
    h = { }
    current_index_view_type = document_index_view_type(query_params)
    h[:view] = current_index_view_type unless current_index_view_type == default_document_index_view_type

    search_action_path(h)
  end

  # Create a link back to the index screen, keeping the user's facet, query and paging choices intact by using session.
  # @example
  #   link_back_to_catalog(label: 'Back to Search')
  #   link_back_to_catalog(label: 'Back to Search', route_set: my_engine)
  def link_back_to_catalog(opts={:label=>nil})
    scope = opts.delete(:route_set) || self
    query_params = current_search_session.try(:query_params) || {}
    
    if search_session['counter']
      per_page = (search_session['per_page'] || default_per_page).to_i
      counter = search_session['counter'].to_i

      query_params[:per_page] = per_page unless search_session['per_page'].to_i == default_per_page
      query_params[:page] = ((counter - 1)/ per_page) + 1
    end

    link_url = scope.url_for(query_params)
    label = opts.delete(:label)

    if link_url =~ /bookmarks/
      label ||= t('blacklight.back_to_bookmarks')
    end

    label ||= t('blacklight.back_to_search')

    link_to label, link_url, opts
  end

  # Search History and Saved Searches display
  def link_to_previous_search(params)
    link_to(render_search_to_s(params), search_action_path(params))
  end

  # @overload params_for_search(source_params, params_to_merge)
  #   Merge the source params with the params_to_merge hash
  #   @param [Hash] Hash 
  #   @param [Hash] Hash to merge into above
  # @overload params_for_search(params_to_merge)
  #   Merge the current search parameters with the 
  #      parameters provided. 
  #   @param [Hash] Hash to merge into the parameters
  # @overload params_for_search
  #   Returns the current search parameters after being sanitized by #sanitize_search_params
  # @yield [params] The merged parameters hash before being sanitized
  def params_for_search(*args, &block)

    source_params, params_to_merge = case args.length
    when 0
      [params, {}]
    when 1
      [params, args.first]
    when 2
      [args.first, args.last]
    else
      raise ArgumentError.new "wrong number of arguments (#{args.length} for 0..2)"
    end

    # params hash we'll return
    my_params = source_params.dup.merge(params_to_merge.dup)

    if block_given?
      yield my_params
    end

    if my_params[:page] and (my_params[:per_page] != source_params[:per_page] or my_params[:sort] != source_params[:sort] )
      my_params[:page] = 1
    end

    sanitize_search_params(my_params)
  end

  ##
  # Sanitize the search parameters by removing unnecessary parameters
  # from the provided parameters
  # @param [Hash] Hash of parameters
  def sanitize_search_params source_params

    my_params = source_params.reject { |k,v| v.nil? }

    my_params.except(:action, :controller, :id, :commit, :utf8)
  end

  ##
  # Reset any search parameters that store search context
  # and need to be reset when e.g. constraints change
  def reset_search_params source_params
    sanitize_search_params(source_params).except(:page, :counter).with_indifferent_access
  end

  # adds the value and/or field to params[:f]
  # Does NOT remove request keys and otherwise ensure that the hash
  # is suitable for a redirect. See
  # add_facet_params_and_redirect
  def add_facet_params(field, item, source_params = params)

    if item.respond_to? :field
      field = item.field
    end

    facet_config = facet_configuration_for_field(field)

    value = facet_value_for_facet_item(item)

    p = reset_search_params(source_params)
    p[:f] = (p[:f] || {}).dup # the command above is not deep in rails3, !@#$!@#$
    p[:f][field] = (p[:f][field] || []).dup

    if facet_config.single and not p[:f][field].empty?
      p[:f][field] = []
    end
    
    p[:f][field].push(value)

    if item and item.respond_to?(:fq) and item.fq
      item.fq.each do |f,v|
        p = add_facet_params(f, v, p)
      end
    end

    p
  end

  # Used in catalog/facet action, facets.rb view, for a click
  # on a facet value. Add on the facet params to existing
  # search constraints. Remove any paginator-specific request
  # params, or other request params that should be removed
  # for a 'fresh' display. 
  # Change the action to 'index' to send them back to
  # catalog/index with their new facet choice. 
  def add_facet_params_and_redirect(field, item)
    new_params = add_facet_params(field, item)

    # Delete any request params from facet-specific action, needed
    # to redir to index action properly. 
    new_params.except! *Blacklight::Solr::FacetPaginator.request_keys.values

    new_params 
  end

  # copies the current params (or whatever is passed in as the 3rd arg)
  # removes the field value from params[:f]
  # removes the field if there are no more values in params[:f][field]
  # removes additional params (page, id, etc..)
  def remove_facet_params(field, item, source_params=params)
    if item.respond_to? :field
      field = item.field
    end

    value = facet_value_for_facet_item(item)

    p = reset_search_params(source_params)
    # need to dup the facet values too,
    # if the values aren't dup'd, then the values
    # from the session will get remove in the show view...
    p[:f] = (p[:f] || {}).dup
    p[:f][field] = (p[:f][field] || []).dup
    p[:f][field] = p[:f][field] - [value]
    p[:f].delete(field) if p[:f][field].size == 0
    p.delete(:f) if p[:f].empty?
    p
  end

  if ::Rails.version < "4.0"
    def asset_url *args
      "#{request.protocol}#{request.host_with_port}#{asset_path(*args)}"
    end
  end
end
