class PostsController < ApplicationController
  before_filter :member_only, :except => [:show, :show_seq, :index, :home, :random]
  before_filter :builder_only, :only => [:copy_notes]
  before_filter :enable_cors, :only => [:index, :show]
  respond_to :html, :xml, :json
  rescue_from PostSets::SearchError, :with => :rescue_exception
  rescue_from Post::SearchError, :with => :rescue_exception
  rescue_from ActiveRecord::StatementInvalid, :with => :rescue_exception
  rescue_from ActiveRecord::RecordNotFound, :with => :rescue_exception

  def index
    if params[:md5].present?
      @post = Post.find_by_md5(params[:md5])
      redirect_to post_path(@post)
    else
      limit = params[:limit] || (params[:tags] =~ /(?:^|\s)limit:(\d+)(?:$|\s)/ && $1) || CurrentUser.user.per_page
      @random = params[:random] || params[:tags] =~ /(?:^|\s)order:random(?:$|\s)/
      @post_set = PostSets::Post.new(tag_query, params[:page], limit, raw: params[:raw], random: @random, format: params[:format], read_only: params[:ro])
      @posts = @post_set.posts
      respond_with(@posts) do |format|
        format.atom
        format.xml do
          render :xml => @posts.to_xml(:root => "posts")
        end
      end
    end
  end

  def show
    @post = Post.find(params[:id])
    @post_flag = PostFlag.new(:post_id => @post.id)
    @post_appeal = PostAppeal.new(:post_id => @post.id)
    
    include_deleted = @post.is_deleted? || (@post.parent_id.present? && @post.parent.is_deleted?) || CurrentUser.user.show_deleted_children?
    @parent_post_set = PostSets::PostRelationship.new(@post.parent_id, :include_deleted => include_deleted)
    @children_post_set = PostSets::PostRelationship.new(@post.id, :include_deleted => include_deleted)
    respond_with(@post)
  end

  def show_seq
    context = PostSearchContext.new(params)
    if context.post_id
      redirect_to(post_path(context.post_id, :tags => params[:tags]))
    else
      redirect_to(post_path(params[:id], :tags => params[:tags]))
    end
  end

  def update
    @post = Post.find(params[:id])

    if @post.visible?
      @post.update_attributes(params[:post], :as => CurrentUser.role)
    end

    save_recent_tags
    respond_with_post_after_update(@post)
  end

  def revert
    @post = Post.find(params[:id])
    @version = PostVersion.find(params[:version_id])

    if @post.visible?
      @post.revert_to!(@version)
    end
    
    respond_with(@post) do |format|
      format.js
    end
  end

  def copy_notes
    @post = Post.find(params[:id])
    @other_post = Post.find(params[:other_post_id].to_i)
    @post.copy_notes_to(@other_post)
    
    if @post.errors.any?
      @error_message = @post.errors.full_messages.join("; ")
      render :json => {:success => false, :reason => @error_message}.to_json, :status => 400
    else
      head :no_content
    end
  end

  def unvote
    @post = Post.find(params[:id])
    @post.unvote!
  rescue PostVote::Error => x
    @error = x
  end

  def home
    if CurrentUser.user.is_anonymous?
      redirect_to intro_explore_posts_path
    else
      redirect_to posts_path(:tags => params[:tags])
    end
  end

  def random
    count = Post.fast_count(params[:tags], :statement_timeout => CurrentUser.user.statement_timeout)
    @post = Post.tag_match(params[:tags]).reorder("").offset(rand(count)).first
    raise ActiveRecord::RecordNotFound if @post.nil?
    redirect_to post_path(@post, :tags => params[:tags])
  end

  def mark_as_translated
    @post = Post.find(params[:id])
    @post.mark_as_translated(params[:post])
    respond_with_post_after_update(@post)
  end

private
  def tag_query
    params[:tags] || (params[:post] && params[:post][:tags])
  end

  def save_recent_tags
    if @post
      tags = Tag.scan_tags(@post.tag_string)
      tags = (TagAlias.to_aliased(tags) + Tag.scan_tags(cookies[:recent_tags])).uniq.slice(0, 30)
      cookies[:recent_tags] = tags.join(" ")
      cookies[:recent_tags_with_categories] = Tag.categories_for(tags).to_a.flatten.join(" ")
    end
  end

  def respond_with_post_after_update(post)
    respond_with(post) do |format|
      format.html do
        if post.errors.any?
          @error_message = post.errors.full_messages.join("; ")
          render :template => "static/error", :status => 500
        else
          response_params = {:tags => params[:tags_query], :pool_id => params[:pool_id], :favgroup_id => params[:favgroup_id]}
          response_params.reject!{|key, value| value.blank?}
          redirect_to post_path(post, response_params)
        end
      end

      format.json do
        render :json => post.to_json
      end
    end
  end
end
