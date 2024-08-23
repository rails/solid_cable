class RoomsController < ApplicationController
  before_action :set_room, only: %i[ show edit update destroy ]

  # GET /rooms
  def index
    @rooms = Room.all
  end

  # GET /rooms/1
  def show
  end

  # GET /rooms/new
  def new
    @room = Room.new
  end

  # GET /rooms/1/edit
  def edit
  end

  # POST /rooms
  def create
    @room = Room.new(room_params)

    if @room.save
      redirect_to @room, notice: "Room was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /rooms/1
  def update
    if @room.update(room_params)
      redirect_to @room, notice: "Room was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /rooms/1
  def destroy
    @room.destroy!
    redirect_to rooms_url, notice: "Room was successfully destroyed.", status: :see_other
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_room
      @room = Room.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def room_params
      params.require(:room).permit(:name)
    end
end
